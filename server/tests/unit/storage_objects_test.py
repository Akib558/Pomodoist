"""Unit tests only: no Docker daemon, provider, database or application is used."""
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('storage_objects', Path(__file__).parents[2] / 'scripts/storage-objects.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class StorageArchiveTest(unittest.TestCase):
    def test_rejects_archive_traversal_and_links(self):
        for name, kind in [('../secret', tarfile.REGTYPE), ('/secret', tarfile.REGTYPE), ('x', tarfile.SYMTYPE), ('x', tarfile.LNKTYPE)]:
            with self.subTest(name=name, kind=kind), tempfile.TemporaryFile() as data:
                with tarfile.open(fileobj=data, mode='w') as archive:
                    member = tarfile.TarInfo(name)
                    member.type = kind
                    archive.addfile(member)
                data.seek(0)
                with tarfile.open(fileobj=data) as archive:
                    with self.assertRaises(ValueError):
                        module.safe_members(archive)

    def test_verify_accepts_object_bytes_without_external_commands(self):
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / 'storage.tar.gz')
            with tarfile.open(path, 'w:gz') as archive:
                member = tarfile.TarInfo('tenant/bucket/id/version')
                member.size = 4
                archive.addfile(member, io.BytesIO(b'data'))
            with patch.object(module.sys, 'argv', ['storage-objects.py', 'verify', path]), patch.object(module.subprocess, 'run') as run:
                module.main()
                run.assert_not_called()

    def test_roundtrip_bytes_uses_configured_provider_without_deleting_other_keys(self):
        config = {'services': {'storage': {'environment': {
            'AWS_ACCESS_KEY_ID': 'storage-key', 'AWS_SECRET_ACCESS_KEY': 'storage-secret',
            'REGION': 'custom', 'GLOBAL_S3_ENDPOINT': 'https://provider.invalid',
            'GLOBAL_S3_BUCKET': 'private-files', 'GLOBAL_S3_FORCE_PATH_STYLE': 'true',
        }}}}
        calls = []
        def aws(command, env, check):
            calls.append(command)
            self.assertEqual(env['AWS_ACCESS_KEY_ID'], 'storage-key')
            self.assertNotIn('AWS_SESSION_TOKEN', env)
            self.assertEqual(command[1:3], ['--endpoint-url', 'https://provider.invalid'])
            self.assertNotIn('--delete', command)
            if command[-2] == 's3://private-files':
                target = Path(command[-1]) / 'tenant/bucket/id'
                target.parent.mkdir(parents=True)
                target.write_bytes(b'\x00file\xff')
            else:
                self.assertEqual((Path(command[-2]) / 'tenant/bucket/id').read_bytes(), b'\x00file\xff')
        with tempfile.TemporaryDirectory() as directory, patch.object(module.shutil, 'which', return_value='/fake/aws'), patch.object(module.subprocess, 'check_output', return_value=json.dumps(config)), patch.object(module.subprocess, 'run', side_effect=aws):
            path = str(Path(directory) / 'storage.tar.gz')
            for action in ['backup', 'restore']:
                with patch.object(module.sys, 'argv', ['storage-objects.py', action, path]):
                    module.main()
            self.assertEqual(len(calls), 2)


if __name__ == '__main__':
    unittest.main()
