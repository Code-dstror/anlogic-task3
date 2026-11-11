"""Optional Ruijie ePortal reconnection, with credentials kept on the server."""
from __future__ import annotations

import argparse
import getpass
import json
import os
from pathlib import Path
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import atomic_json, read_json


PORTAL = 'http://portal.example.invalid:8080/eportal/'
PROBE = 'http://www.msftconnecttest.com/connecttest.txt'
PROBE_TEXT = b'Microsoft Connect Test'


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, file_pointer, code, message, headers, new_url):
        return None


def opener():
    return urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())


def double_form(fields):
    safe = "~()*!.'"
    return '&'.join(key + '=' + urllib.parse.quote(urllib.parse.quote(str(value), safe=safe), safe=safe)
                    for key, value in fields.items()).encode('ascii')


def encrypt_password(password, mac, exponent, modulus):
    exponent_number = int(exponent, 16)
    modulus_number = int(modulus, 16)
    if exponent_number != 65537 or not 512 <= modulus_number.bit_length() <= 4096:
        raise ValueError('Unsupported ePortal public key')
    raw = (password + '>' + (mac or '111111111')).encode('utf-16-le', errors='surrogatepass')
    units = [int.from_bytes(raw[offset:offset + 2], 'little') for offset in range(0, len(raw), 2)][::-1]
    chunk_size = 2 * ((modulus_number.bit_length() - 1) // 16)
    units.extend([0] * (-len(units) % chunk_size))
    blocks = []
    for offset in range(0, len(units), chunk_size):
        block = sum((units[offset + position] + (units[offset + position + 1] << 8)) << (8 * position)
                    for position in range(0, chunk_size, 2))
        encrypted = format(pow(block, exponent_number, modulus_number), 'x')
        blocks.append(encrypted.rjust((len(encrypted) + 3) // 4 * 4, '0'))
    return ' '.join(blocks)


def portal_query(location, portal=PORTAL):
    expected = urllib.parse.urlsplit(portal)
    actual = urllib.parse.urlsplit(location)
    if (actual.scheme, actual.hostname, actual.port) != (expected.scheme, expected.hostname, expected.port):
        return None
    if not actual.path.startswith('/eportal/') or actual.path.endswith('success.jsp') or not actual.query:
        return None
    values = urllib.parse.parse_qs(actual.query)
    if 'userIndex' in values or not any(name in values for name in ('wlanuserip', 'userip', 'mac', 'wlanacip')):
        return None
    return actual.query


def probe(connection, portal=PORTAL):
    request = urllib.request.Request(PROBE, headers={'User-Agent': 'TD-campus-reconnect/1'})
    try:
        with connection.open(request, timeout=5) as response:
            body = response.read(256 * 1024)
            if body.strip() == PROBE_TEXT:
                return True, None
            text = body.decode('utf-8', errors='replace')
            for location in re.findall(r'https?://[^\s\'"<>]+', text):
                query = portal_query(location.replace('&amp;', '&'), portal)
                if query:
                    return False, query
    except urllib.error.HTTPError as error:
        location = error.headers.get('Location', '')
        return False, portal_query(location, portal)
    except (OSError, urllib.error.URLError):
        pass
    return False, None


def api(connection, portal, method, fields):
    if method not in ('pageInfo', 'login') or portal != PORTAL:
        raise ValueError('Only the enrolled portal pageInfo/login endpoints are used')
    request = urllib.request.Request(portal + 'InterFace.do?method=' + method,
                                     data=double_form(fields),
                                     headers={'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
                                              'User-Agent': 'Mozilla/5.0 TD-campus-reconnect/1',
                                              'Referer': portal + 'index.jsp'}, method='POST')
    with connection.open(request, timeout=8) as response:
        if urllib.parse.urlsplit(response.geturl()).hostname != 'portal.example.invalid':
            raise ValueError('Portal response came from another host')
        return json.loads(response.read(1024**2).decode('utf-8-sig'))


def reconnect(root):
    path = Path(root) / 'network-auth.json'
    if not path.is_file():
        return {'state': 'DISABLED'}
    if path.is_symlink() or (os.name == 'posix' and (path.stat().st_mode & 0o077 or path.stat().st_uid != os.getuid())):
        return {'state': 'LOCAL_CREDENTIAL_PERMISSIONS_REQUIRED'}
    config = read_json(path)
    if config.get('portal') != PORTAL:
        return {'state': 'PORTAL_CONFIGURATION_REQUIRED'}
    connection = opener()
    online, query = probe(connection)
    if online:
        return {'state': 'ONLINE'}
    if not query:
        return {'state': 'OFFLINE_WAITING_FOR_PORTAL_REDIRECT'}
    try:
        page = api(connection, PORTAL, 'pageInfo', {'queryString': query})
        if page.get('validCodeUrl') or str(page.get('isCheckSmsAuth')).lower() == 'true':
            return {'state': 'MANUAL_CAPTCHA_OR_SMS_REQUIRED'}
        if str(page.get('passwordEncrypt')).lower() not in ('true', 'false'):
            return {'state': 'PORTAL_CONFIGURATION_UNAVAILABLE'}
        username = page.get('prefixValue', '') + config['username']
        password = config['password']
        encrypted = str(page.get('passwordEncrypt')).lower() == 'true'
        if encrypted:
            mac_match = re.search(r'(?:^|&)mac=([^&]*)', query)
            mac = mac_match.group(1) if mac_match and mac_match.group(1) else '111111111'
            password = encrypt_password(password, mac, page['publicKeyExponent'], page['publicKeyModulus'])
        result = api(connection, PORTAL, 'login',
                     dict(userId=username, password=password, service=config.get('service', ''), queryString=query,
                          operatorPwd='', operatorUserId='', validcode='', passwordEncrypt=str(encrypted).lower()))
        if result.get('result') != 'success':
            return {'state': 'AUTHENTICATION_FAILED'}
        online, unused_query = probe(connection)
        return {'state': 'ONLINE' if online else 'AUTHENTICATED_WAITING_FOR_EXTERNAL_NETWORK'}
    except Exception:
        return {'state': 'PORTAL_UNAVAILABLE_RETRY_NEXT_MINUTE'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('configure', 'check'))
    parser.add_argument('--root', type=Path, default=(Path.home() / 'td_simple'))
    arguments = parser.parse_args()
    if arguments.action == 'configure':
        if os.name != 'posix':
            raise ValueError('Configure credentials in FinalShell on the server, not on the Windows client')
        os.umask(0o077)
        username = input('Campus username: ').strip()
        password = getpass.getpass('Campus password (hidden): ')
        service = input('Service name (Enter for the normal campus service): ').strip()
        if not username or not password:
            raise ValueError('Username and password are required')
        arguments.root.mkdir(parents=True, exist_ok=True)
        path = arguments.root / 'network-auth.json'
        atomic_json(path, dict(portal=PORTAL, username=username, password=password, service=service))
        os.chmod(path, 0o600)
        print('Saved server-local credentials with mode 600. They are never included in Git reports.')
    else:
        print(json.dumps(reconnect(arguments.root), ensure_ascii=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
