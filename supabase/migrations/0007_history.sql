-- IT Brain — 0007: Historial (append-only)
-- Ver docs/05-base-de-datos.md §6 — nunca se pierde información (Constitución regla 5/13)

create table entity_history (
  id          uuid primary key default uuid_generate_v4(),
  org_id      uuid not null references organizations(id) on delete cascade,
  entity_id   uuid not null references entities(id) on delete cascade,
  field       text not null,        -- nombre de campo, o 'relationship' para altas/bajas de arista
  old_value   jsonb,
  new_value   jsonb,
  changed_by  uuid references auth.users(id),
  changed_at  timestamptz not null default now(),
  reason      text
);
create index idx_history_entity on entity_history(entity_id, changed_at desc);

-- Trigger: registrar cambios de campos base (name, status, data)
create or replace function entities_log_history() returns trigger as $$
begin
  if old.name is distinct from new.name then
    insert into entity_history(org_id, entity_id, field, old_value, new_value, changed_by)
    values (new.org_id, new.id, 'name', to_jsonb(old.name), to_jsonb(new.name), new.updated_by);
  end if;
  if old.status is distinct from new.status then
    insert into entity_history(org_id, entity_id, field, old_value, new_value, changed_by)
    values (new.org_id, new.id, 'status', to_jsonb(old.status), to_jsonb(new.status), new.updated_by);
  end if;
  if old.data is distinct from new.data then
    insert into entity_history(org_id, entity_id, field, old_value, new_value, changed_by)
    values (new.org_id, new.id, 'data', old.data, new.data, new.updated_by);
  end if;
  return new;
end;
$$ language plpgsql;

create trigger trg_entities_history
  after update on entities
  for each row execute function entities_log_history();

-- Append-only real: nadie (salvo service_role) puede tocar el historial
revoke update, delete on entity_history from authenticated;
