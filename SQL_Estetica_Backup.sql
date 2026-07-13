-- ======================================================================
--  ESTÉTICA — Copias de seguridad / Rollback · idempotente
--  Base compartida: pcxlhgdpxfuybzfsquem · tabla estetica_backups (jsonb "datos")
--  Corré primero SQL_Estetica.sql. Este agrega historial + rollback.
--  Conserva las últimas 10 copias por licencia (la 11ª se borra sola).
-- ======================================================================

create table if not exists public.estetica_backups_hist (
  id        bigserial primary key,
  tenant_id text        not null,
  datos     jsonb       not null,
  guardado  timestamptz not null default now()
);
create index if not exists estetica_hist_tenant_idx on public.estetica_backups_hist (tenant_id, guardado desc);
alter table public.estetica_backups_hist enable row level security;
revoke all on public.estetica_backups_hist from anon, authenticated;

create or replace function public.estetica_hist_guardar()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if OLD.datos is not null and OLD.datos <> '{}'::jsonb and OLD.datos is distinct from NEW.datos then
    insert into public.estetica_backups_hist (tenant_id, datos, guardado) values (OLD.tenant_id, OLD.datos, now());
    delete from public.estetica_backups_hist
      where id in (select id from public.estetica_backups_hist where tenant_id = OLD.tenant_id order by guardado desc offset 10);
  end if;
  return NEW;
end $$;
drop trigger if exists estetica_hist_trg on public.estetica_backups;
create trigger estetica_hist_trg before update on public.estetica_backups
  for each row execute function public.estetica_hist_guardar();

create or replace function public.estetica_hist_listar(p_codigo text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare arr jsonb;
begin
  if auth.uid() is null then return '[]'::jsonb; end if;
  if not exists (select 1 from public.tl_miembros where user_id = auth.uid() and tenant_id = p_codigo) then return '[]'::jsonb; end if;
  select coalesce(jsonb_agg(x order by (x->>'guardado') desc), '[]'::jsonb) into arr
  from (
    select jsonb_build_object(
      'id', id, 'guardado', guardado,
      'servicios', coalesce(jsonb_array_length(datos->'serv'), 0),
      'productos', coalesce(jsonb_array_length(datos->'prod'), 0),
      'turnos', coalesce(jsonb_array_length(datos->'turnos'), 0),
      'colaboradores', coalesce(jsonb_array_length(datos->'colabs'), 0)
    ) as x
    from public.estetica_backups_hist where tenant_id = p_codigo order by guardado desc limit 10
  ) s;
  return arr;
end $$;
grant execute on function public.estetica_hist_listar(text) to authenticated;

create or replace function public.estetica_hist_restaurar(p_codigo text, p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d jsonb;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  if not exists (select 1 from public.tl_miembros where user_id = auth.uid() and tenant_id = p_codigo) then
    return jsonb_build_object('ok', false, 'error', 'no_miembro'); end if;
  select datos into d from public.estetica_backups_hist where id = p_id and tenant_id = p_codigo limit 1;
  if d is null then return jsonb_build_object('ok', false, 'error', 'sin_copia'); end if;
  update public.estetica_backups set datos = d, updated_at = now() where tenant_id = p_codigo;
  return jsonb_build_object('ok', true, 'datos', d);
end $$;
grant execute on function public.estetica_hist_restaurar(text, bigint) to authenticated;

create or replace function public.estetica_hist_snapshot(p_codigo text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d jsonb; tot int;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  if not exists (select 1 from public.tl_miembros where user_id = auth.uid() and tenant_id = p_codigo) then
    return jsonb_build_object('ok', false, 'error', 'no_miembro'); end if;
  select datos into d from public.estetica_backups where tenant_id = p_codigo limit 1;
  if d is null or d = '{}'::jsonb then return jsonb_build_object('ok', false, 'error', 'sin_datos'); end if;
  insert into public.estetica_backups_hist (tenant_id, datos, guardado) values (p_codigo, d, now());
  delete from public.estetica_backups_hist
    where id in (select id from public.estetica_backups_hist where tenant_id = p_codigo order by guardado desc offset 10);
  select count(*) into tot from public.estetica_backups_hist where tenant_id = p_codigo;
  return jsonb_build_object('ok', true, 'total', tot);
end $$;
grant execute on function public.estetica_hist_snapshot(text) to authenticated;
