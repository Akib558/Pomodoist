"""Source contract checks only; these do not execute PostgreSQL or prove RLS."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = next((ROOT / 'supabase/migrations').glob('20260929115235_*.sql'))
SQL = MIGRATION.read_text()

class ProjectFilesContract(unittest.TestCase):
    def test_cleanup_loop_variable_does_not_shadow_upload_table_alias(self):
        migrations = sorted((ROOT / 'supabase/migrations').glob('*.sql'))
        definitions = [p.read_text().split('CREATE OR REPLACE FUNCTION private.pomodoist_collaboration_storage_cleanup(', 1)[1].split('end $$;', 1)[0]
                       for p in migrations if 'CREATE OR REPLACE FUNCTION private.pomodoist_collaboration_storage_cleanup(' in p.read_text()]
        cleanup = definitions[-1]
        self.assertNotIn('declare u record;', cleanup)
        self.assertIn('declare expired_upload_id uuid;', cleanup)
        self.assertIn('private.pomodoist_file_delete(expired_upload_id)', cleanup)
        self.assertIn('where u.object_path=d.object_path', cleanup)

    def test_file_migration_can_be_consumed_by_private_core_assembler(self):
        self.assertIn('_pomodoist_core_', MIGRATION.name)

    def test_unshare_retains_existing_response_and_relation_identities(self):
        unshare = SQL.split("elsif action='unshare' then", 1)[1].split("elsif action='publicLink'", 1)[0]
        self.assertIn("'restored',", unshare)
        self.assertIn("'sharedEntityId',c.shared_entity_id", unshare)
        self.assertIn("'labelId',c.personal->>'labelId'", unshare)
        self.assertIn("v->>'sharedEntityId'=e.entity_id", unshare)
        self.assertIn('jsonb_array_length(rows)', unshare)

    def test_personal_and_shared_files_use_one_authority(self):
        self.assertIn('CREATE OR REPLACE FUNCTION private.pomodoist_files(', SQL)
        self.assertIn('return private.pomodoist_files(p_request)', SQL)
        self.assertIn('quota_user_id', SQL)
        self.assertIn('personal_user_id', SQL)

    def test_clients_cannot_write_attachment_projections(self):
        self.assertIn("v_entity_type = 'attachment'", SQL)
        self.assertIn('Attachment metadata is server-authored', SQL)

    def test_late_upload_capabilities_are_not_acknowledged_early(self):
        self.assertIn('retain_until', SQL)
        self.assertIn('storage_deleted_at', SQL)
        self.assertIn("expires_at + interval '2 hours'", SQL)

    def test_unshare_preserves_files_and_new_content(self):
        self.assertIn('personal_user_id=actor, scope_id=null', SQL)
        self.assertIn("entity_type in ('project','task','section','label','task_label','task_kanban_status','task_completion')", SQL)
        self.assertIn('pomodoist-files-cleanup', SQL)

    def test_outer_writers_acquire_lifecycle_before_existing_locks(self):
        lock_patch = SQL.split('do $lock_order$', 1)[1].split('end $lock_order$;', 1)[0]
        for signature in (
            'public.pomodoist_google_calendar_service(text,uuid,jsonb)',
            'public.pomodoist_openclaw_action(uuid,uuid,uuid,uuid,text,text,bigint,jsonb,jsonb)',
            'public.push_pomodoist_draft_changes(text,text,jsonb)',
            'public.push_pomodoist_telegram_changes(bigint,uuid,uuid,jsonb)',
            'public.complete_pomodoist_telegram_link(bytea,uuid)',
        ):
            self.assertIn(signature, lock_patch)
        self.assertIn("body_start:=strpos(definition,E'\\nbegin\\n')", lock_patch)
        self.assertIn("if body_start=0 then raise exception", lock_patch)
        self.assertIn("E'\\nbegin\\n  perform pg_catalog.pg_advisory_xact_lock", lock_patch)
        self.assertIn("''pomodoist-file-lifecycle''", lock_patch)
        self.assertIn("from body_start for length(E'\\nbegin\\n')", lock_patch)
        self.assertIn('pomodoist_files_account_delete_lock before delete on auth.users\n'
                      '  for each statement', SQL)

    def test_restore_removes_transfer_guard_before_live_rows(self):
        unshare = SQL.split("elsif action='unshare' then", 1)[1]
        self.assertLess(unshare.index('delete from private.pomodoist_transferred_entities'),
                        unshare.index('insert into public.sync_entities'))

    def test_scope_deletion_keeps_retired_upload_identity(self):
        deletion = SQL.split("elsif action='delete' then", 1)[1].split("elsif action='unshare' then", 1)[0]
        self.assertLess(deletion.index('set scope_id=null,personal_user_id=actor'),
                        deletion.index('delete from private.pomodoist_scopes'))

    def test_quota_payer_and_finished_replay_are_stable(self):
        authority = SQL.split('CREATE OR REPLACE FUNCTION private.pomodoist_files(', 1)[1].split('end $$;', 1)[0]
        self.assertIn("when scope is not null and public.has_active_pomodoist_paid_entitlement(owner_id) then owner_id", authority)
        self.assertIn("if action='finishUpload' then payer:=u.quota_user_id", authority)
        self.assertLess(authority.index("elsif action='finishUpload' and u.finished_at is not null"),
                        authority.index('insert into private.pomodoist_upload_months'))
        self.assertIn("editable:=role_name in ('administrator','member')", authority)
        self.assertIn('used_month+held+u.bytes>1000000000', authority)
        self.assertIn('used_year+held+u.bytes>5000000000', authority)
        self.assertIn("errcode='P0002'", authority)

if __name__ == '__main__':
    unittest.main()
