-- Keep the existing cleanup worker compatible while its header contract evolves.
alter table private.pomodoist_files_cleanup_request enable row level security;

do $compatibility$
declare definition text; original text; replacement text;
begin
  definition := pg_catalog.pg_get_functiondef('private.invoke_pomodoist_files_cleanup()'::regprocedure);
  original := $old$headers:=jsonb_build_object('Content-Type','application/json','X-Pomodoist-Cleanup-Secret',secret)$old$;
  replacement := $new$headers:=jsonb_build_object('Content-Type','application/json',
      'Authorization','Bearer '||secret,'X-Pomodoist-Cleanup-Secret',secret)$new$;
  if pg_catalog.strpos(definition, original) = 0 then
    raise exception 'Unexpected file cleanup header definition';
  end if;
  execute pg_catalog.replace(definition, original, replacement);
end $compatibility$;
