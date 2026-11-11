"""Native run configuration, without executable remote Tcl hooks."""
from __future__ import annotations

import math
import re


RUN_DEFAULTS = {'syn_1': 'Default_Synthesis_Strategy', 'phy_1': 'Default_PhysicalDesign_Strategy'}
PARAMETER_NAME = re.compile(r'[A-Za-z_][A-Za-z0-9_]*\Z')


def tcl_word(value):
    result = str(value)
    for original, replacement in (('\\', '\\\\'), ('"', '\\"'), ('$', '\\$'),
                                  ('[', '\\['), (']', '\\]'), ('\n', '\\n'), ('\r', '\\r')):
        result = result.replace(original, replacement)
    return '"' + result + '"'


def scalar(value):
    return (type(value) in (str, int, float, bool) and
            (not isinstance(value, str) or len(value) <= 4096 and '\0' not in value) and
            (not isinstance(value, float) or math.isfinite(value)))


def validate_run_options(project):
    options = project.get('td_options', {})
    if not isinstance(options, dict) or set(options) - RUN_DEFAULTS.keys():
        raise ValueError('td_options maps syn_1 and phy_1 to their Run Properties')
    for run, sections in options.items():
        if not isinstance(sections, dict):
            raise ValueError('Each TD run needs a property-section dictionary')
        for section, parameters in sections.items():
            if not isinstance(section, str) or not PARAMETER_NAME.fullmatch(section) or not isinstance(parameters, dict):
                raise ValueError('Use native TD property section names and parameter dictionaries')
            for name, value in parameters.items():
                valid_value = scalar(value) or (isinstance(value, list) and len(value) <= 64 and all(scalar(item) for item in value))
                if not isinstance(name, str) or not PARAMETER_NAME.fullmatch(name) or not valid_value:
                    raise ValueError('Use native TD property names and scalar values or scalar lists')
                if (section == 'flow' and name in ('thread', 'enable_seed') or
                        section == 'place' and name == 'seed'):
                    raise ValueError('Configure threads/seeds through their dedicated fields, not td_options')
                if any(part in name.lower() for part in ('tcl', 'script', 'command', 'hook')):
                    raise ValueError('Remote Run Properties do not accept executable script hooks')
    strategies = project.get('td_strategies', {})
    if (not isinstance(strategies, dict) or set(strategies) - RUN_DEFAULTS.keys() or
            any(not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_. -]{0,119}', value)
                for value in strategies.values())):
        raise ValueError('td_strategies maps syn_1/phy_1 to native strategy names')
    reset = project.get('td_reset', [])
    if (not isinstance(reset, list) or any(not isinstance(run, str) or run not in RUN_DEFAULTS for run in reset) or
            len(set(reset)) != len(reset)):
        raise ValueError('td_reset is a list of distinct syn_1/phy_1 run names')


def parameter_value(value):
    if isinstance(value, list):
        return '[list ' + ' '.join(parameter_value(item) for item in value) + ']'
    return tcl_word(('on' if value else 'off') if type(value) is bool else value)


def parameter_lines(project, reuse):
    lines = []
    for run, strategy in project.get('td_strategies', {}).items():
        if run == 'syn_1' and reuse or run == 'phy_1' and reuse >= 2:
            continue
        words = tcl_word(run) + ' ' + tcl_word(strategy)
        lines += ['    puts ' + tcl_word('TD_SIMPLE_STRATEGY ' + words),
                  '    set_strategy -run ' + words]
    for run, sections in project.get('td_options', {}).items():
        if run == 'syn_1' and reuse:
            continue
        for section, settings in sections.items():
            for name, value in settings.items():
                words = ' '.join(tcl_word(item) for item in (run, section, name)) + ' ' + parameter_value(value)
                lines += ['    puts ' + tcl_word('TD_SIMPLE_PROPERTY ' + words),
                          '    set_param -run ' + words]
    return lines


def reset_run_options(text, runs):
    """Clear only selected job-local AL runs; let TD restore device defaults."""
    remaining = set(runs)

    def replace(match):
        block = match.group(0)
        name = re.search(r'\bName="([^"]+)"', match.group(1))
        run = name.group(1) if name else None
        if run not in remaining:
            return block
        remaining.remove(run)
        block = re.sub(r'<Strategy\b[^>]*(?:/>|>.*?</Strategy>)', '', block, flags=re.DOTALL)
        block = re.sub(r'<UserParams\b[^>]*(?:/>|>.*?</UserParams>)', '', block, flags=re.DOTALL)
        return block.replace('</Run>', '<Strategy Name="' + RUN_DEFAULTS[run] + '"/><UserParams/></Run>')

    result = re.sub(r'<Run\b([^>]*)>.*?</Run>', replace, text, flags=re.DOTALL)
    if remaining:
        raise ValueError('Cannot reset missing native runs: ' + ', '.join(sorted(remaining)))
    return result
