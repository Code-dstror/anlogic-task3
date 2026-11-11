"""Host-only contract checks; no FPGA RTL, driver or board is exercised."""
import copy
import unittest
from dataclasses import make_dataclass
import switch_probe as probe


class ProbeTests(unittest.TestCase):
    def setUp(self):
        p, _ = probe.protocol()
        self.after = dict(schema=1, owner={'bdf': 'test-only', 'fd_generation': 7},
            identity_stable=True, leased=0, unread=False,
            transport=dict(running=0, stopped=1, quarantined=0, submitted=100, completed=100),
            registers=dict(control=0, status=p.PCIE_STATUS_LINK_UP | p.PCIE_STATUS_USER_RESET_RELEASED |
                           p.PCIE_STATUS_SESSION_REARM_READY, cfg_session=3, active_session=3,
                           cfg_status=p.PCIE_CFG_STATUS_SESSION_READY, cfg_error=0, epoch=0,
                           mode=p.PCIE_CFG_MODE_COLOR, quality=75, stereo_status=0, stereo_error=0,
                           stereo_mode=0, profile=p.PCIE_CFG_PROFILE_MONO1920, cameras=1,
                           record_version=p.PROTOCOL_VERSION, record_header=p.HEADER_LENGTH))
        self.before = copy.deepcopy(self.after)
        self.before['registers']['cfg_session'] = 2

    def test_nonzero_lifetime_counters_are_allowed(self):
        self.assertEqual(probe.evaluate(self.before, self.after)['issues'], [])

    def test_bad_boundaries_are_blocked(self):
        cases = [('registers','cfg_session',2), ('registers','active_session',2),
                 ('registers','stereo_status',4), ('registers','epoch',1),
                 ('registers','record_version',4), ('registers','status',3),
                 ('registers','cfg_error',1), ('registers','stereo_mode',1),
                 ('transport','running',1), ('transport','quarantined',1),
                 ('transport','completed',99), (None,'leased',1),
                 (None,'unread',True), (None,'identity_stable',False),
                 (None,'owner',{'bdf':'different'})]
        for section, key, value in cases:
            with self.subTest(section=section, key=key):
                after = copy.deepcopy(self.after)
                (after[section] if section else after)[key] = value
                self.assertTrue(probe.evaluate(self.before, after)['issues'])

    def test_collector_uses_only_read_owner_methods(self):
        p, _ = probe.protocol()
        Identity = make_dataclass('Identity', [('bdf', str)])
        Snapshot = make_dataclass('Snapshot', [(k, int) for k in self.after['transport']])
        values = {p.PCIE_REG_CFG_SESSION: 3, p.PCIE_REG_CFG_ACTIVE_SESSION: 3}
        class Owner:
            leased_count = 0
            def read32(self, address): return values.get(address, 0)
            def owner_identity(self): return Identity('test-only')
            def snapshot(inner): return Snapshot(**self.after['transport'])
            def poll(self, timeout):
                assert timeout == 0
                return False
        result = probe.collect(Owner())
        self.assertTrue(result['identity_stable'])
        self.assertEqual(result['registers']['cfg_session'], 3)


if __name__ == '__main__':
    unittest.main()
