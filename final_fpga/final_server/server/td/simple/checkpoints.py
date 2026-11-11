"""Fork owned native checkpoints without modifying the completed source run."""
from __future__ import annotations

import copy
from pathlib import Path
import shutil
import os
import time

from common import TERMINAL, atomic_json, contained, job_threads, project_config, read_json
from run_options import RUN_DEFAULTS


STAGES = ('synthesis', 'placement', 'routing', 'bitgen')
TARGET_LEVEL = dict(synth=1, place=2, route=3, full=4, bitgen=4)
DATABASES = (('syn_1', 'gate', 'opt_gate'), ('phy_1', 'place', 'opt_place'), ('phy_1', 'pr', 'opt_route'))


def run_directory(checkout, project):
    root = Path(checkout) if project['root'] == '.' else contained(checkout, project['root'])
    project_file = contained(root, project['al'])
    return project_file.parent / (project_file.stem + '_Runs'), project_file.stem


def continuation(parent, jobs_root, target, seed, changes):
    if parent['state'] not in TERMINAL:
        raise ValueError('Wait for the source job to stop before forking its native checkpoints')
    parent_job = Path(jobs_root) / parent['id']
    result = read_json(parent_job / 'result.json', {})
    stages = result.get('stages', {})
    runs, name = run_directory(parent_job / 'checkout', parent['spec']['project'])
    available = 0
    for index, (run, suffix, step) in enumerate(DATABASES, 1):
        database = runs / run / (name + '_' + suffix + '.db')
        if (stages.get(STAGES[index - 1]) not in ('DONE', 'REUSED') or
                not (runs / run / ('.' + step + '.end.f')).is_file() or
                not database.is_file() or database.stat().st_size == 0):
            break
        if not database.resolve().is_relative_to(parent_job.resolve()):
            raise ValueError('Checkpoint database leaves the owned source job')
        available = index
    if not available:
        raise ValueError('No completed native synthesis checkpoint is available')
    if target == 'bitgen' and available < 3:
        raise ValueError('bitgen-only requires a completed routing checkpoint; use full to finish remaining stages')
    project = copy.deepcopy(parent['spec']['project'])
    project.pop('td_reset', None)
    project.update({key: value for key, value in changes.items() if key not in ('td_options', 'td_strategies')})
    requested_options = changes.get('td_options', {})
    options = project.setdefault('td_options', {})
    reuse = min(available, TARGET_LEVEL[target] - 1)
    strategies = project.setdefault('td_strategies', {})
    for run in changes.get('td_reset', []):
        options.pop(run, None)
        strategies[run] = RUN_DEFAULTS[run]
        reuse = 0 if run == 'syn_1' else min(reuse, 1)
    for run, strategy in changes.get('td_strategies', {}).items():
        if strategies.get(run) != strategy:
            reuse = 0 if run == 'syn_1' else min(reuse, 1)
        strategies[run] = strategy
    for run, sections in requested_options.items():
        for section, settings in sections.items():
            original = options.setdefault(run, {}).setdefault(section, {})
            changed = any(original.get(key) != value for key, value in settings.items())
            if changed:
                if run == 'syn_1' or section in ('design', 'rtl', 'gate'):
                    reuse = 0
                elif section in ('flow', 'place'):
                    reuse = min(reuse, 1)
                elif section == 'route':
                    reuse = min(reuse, 2)
                elif section != 'bitgen':
                    reuse = min(reuse, 1)
            original.update(settings)
    if seed != parent['spec']['seed']:
        reuse = min(reuse, 1)
    if target == 'bitgen' and reuse < 3:
        raise ValueError('These property/seed changes invalidate routing; use full to regenerate the affected stages')
    project['target'] = target
    project = project_config(project)
    attempted = max([available, *(index for index, stage in enumerate(STAGES, 1)
                                 if stages.get(stage) in ('RUNNING', 'DONE', 'REUSED'))])
    resume = dict(job=parent['id'], checkpoint_level=reuse, rollback_steps=max(0, attempted - reuse),
                  synthesis_threads=parent['spec'].get('resume', {}).get('synthesis_threads',
                      parent['spec']['project'].get('synth_threads', job_threads(parent['spec']))))
    return project, resume


def copy_checkpoint(jobs_root, job, spec):
    parent = Path(jobs_root) / spec['resume']['job']
    source = parent / 'checkout'
    if not source.is_dir() or any(path.is_symlink() for path in source.rglob('*')):
        raise ValueError('The source checkpoint is missing or contains linked files')
    partial = job / 'checkpoint.tmp'
    if partial.exists():
        if partial.is_symlink() or partial.resolve().parent != job.resolve():
            raise ValueError('Unexpected temporary checkpoint path')
        shutil.rmtree(partial)
    shutil.copytree(source, partial, ignore=lambda directory, names:
                    [name for name in names if Path(name).suffix.lower() == '.bit'])
    for attempt in range(5):
        try:
            partial.rename(job / 'checkout')
            break
        except PermissionError:
            if os.name != 'nt' or attempt == 4:
                raise
            time.sleep(.1 * (attempt + 1))
    atomic_json(job / 'reused-from.json', dict(source_job=spec['resume']['job'], source_commit=spec['source_commit'],
                                             reused_stages=list(STAGES[:spec['resume']['checkpoint_level']]),
                                             synthesis_threads=spec['resume']['synthesis_threads']))
