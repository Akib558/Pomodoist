#!/usr/bin/env python3
"""Archive/restore private S3 bytes using the same settings as the Storage service."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile


def safe_members(archive):
    for member in archive.getmembers():
        path = Path(member.name)
        if path.is_absolute() or '..' in path.parts or not (member.isfile() or member.isdir()):
            raise ValueError('Unsafe Storage archive member')
    return archive.getmembers()


def main():
    action, archive_name = sys.argv[1:]
    if action not in ('backup', 'restore', 'verify'):
        raise ValueError('Expected backup, restore or verify')
    if action == 'verify':
        with tarfile.open(archive_name, 'r:gz') as archive:
            safe_members(archive)
        return
    if not shutil.which('aws'):
        raise RuntimeError('Install AWS CLI v2 to back up or restore S3 object bytes')
    server = Path(__file__).resolve().parent.parent
    command = ['docker', 'compose', '--project-directory', str(server), '--env-file', str(server / '.env'), '-f', str(server / 'compose.yaml')]
    for overlay in os.environ.get('COMPOSE_OVERLAYS', '').split():
        command += ['-f', str(server / overlay)]
    config = json.loads(subprocess.check_output(command + ['config', '--format', 'json']))
    storage = config['services']['storage']['environment']
    env = dict(os.environ, AWS_ACCESS_KEY_ID=storage['AWS_ACCESS_KEY_ID'], AWS_SECRET_ACCESS_KEY=storage['AWS_SECRET_ACCESS_KEY'], AWS_DEFAULT_REGION=storage['REGION'])
    # Prevent a host's unrelated session token/profile from overriding the configured key pair.
    env.pop('AWS_SESSION_TOKEN', None)
    env.pop('AWS_PROFILE', None)
    endpoint = storage['GLOBAL_S3_ENDPOINT']
    bucket = 's3://' + storage['GLOBAL_S3_BUCKET']
    with tempfile.TemporaryDirectory(prefix='pomodoist-storage-') as temporary:
        directory = Path(temporary)
        config_file = directory / '.aws-backup-config'
        config_file.write_text('[default]\ns3 =\n    addressing_style = ' + ('path' if str(storage.get('GLOBAL_S3_FORCE_PATH_STYLE')).lower() == 'true' else 'virtual') + '\n')
        env['AWS_CONFIG_FILE'] = str(config_file)
        objects = directory / 'objects'
        objects.mkdir()
        aws = ['aws', '--endpoint-url', endpoint, 's3']
        if action == 'backup':
            subprocess.run(aws + ['sync', '--only-show-errors', bucket, str(objects)], env=env, check=True)
            with tarfile.open(archive_name, 'w:gz') as archive:
                for path in sorted(objects.rglob('*')):
                    if path.is_file():
                        archive.add(path, arcname=str(path.relative_to(objects)), recursive=False)
        else:
            with tarfile.open(archive_name, 'r:gz') as archive:
                archive.extractall(objects, members=safe_members(archive), filter='data')
            # Object paths are immutable UUIDs. Keep unrelated/newer keys on partial failures.
            subprocess.run(aws + ['cp', '--recursive', '--only-show-errors', str(objects), bucket], env=env, check=True)


if __name__ == '__main__':
    main()
