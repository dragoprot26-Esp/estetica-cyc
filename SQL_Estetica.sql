-- ======================================================================
--  ESTÉTICA (Aurelia) — Molde CyC · Supabase · idempotente
--  Base compartida: pcxlhgdpxfuybzfsquem · prefijo ESTE-...
--  Depende del molde base ya instalado: tl_miembros, validar_licencia,
--  reclamar_tienda, sincronizar_clave_dueno.
--  Tabla de datos: estetica_backups (columna jsonb "datos" = todo el estado).
--  Correlo COMPLETO en el SQL Editor de Supabase (se puede repetir).
-- ======================================================================

-- 1) Tabla de datos (un local por licencia) ----------------------------
create table if not exists public.estetica_backups (
  tenant_id  text primary key,
  datos      jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.estetica_backups enable row level security;

-- RLS: solo miembros (dueño/colaborador) leen y escriben su propio local.
drop policy if exists estetica_sel on public.estetica_backups;
create policy estetica_sel on public.estetica_backups for select to authenticated
  using (exists (select 1 from public.tl_miembros m where m.user_id = auth.uid() and m.tenant_id = estetica_backups.tenant_id));
drop policy if exists estetica_ins on public.estetica_backups;
create policy estetica_ins on public.estetica_backups for insert to authenticated
  with check (exists (select 1 from public.tl_miembros m where m.user_id = auth.uid() and m.tenant_id = estetica_backups.tenant_id));
drop policy if exists estetica_upd on public.estetica_backups;
create policy estetica_upd on public.estetica_backups for update to authenticated
  using (exists (select 1 from public.tl_miembros m where m.user_id = auth.uid() and m.tenant_id = estetica_backups.tenant_id));

-- 2) Público: catálogo/página de un local (sin login) -------------------
--    Devuelve SOLO lo que ve el cliente (sin colaboradores ni turnos).
create or replace function public.estetica_publica(p_codigo text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d jsonb;
begin
  select datos into d from public.estetica_backups where tenant_id = p_codigo limit 1;
  if d is null then return null; end if;
  return jsonb_build_object(
    'cfg', jsonb_build_object(
       'tema', d->'cfg'->'tema',
       'prodOn', d->'cfg'->'prodOn',
       'activo', d->'cfg'->'activo',
       'textos', d->'cfg'->'textos',
       'heroImg', d->'cfg'->'heroImg',
       'galeria', d->'cfg'->'galeria',
       'inquilinos', d->'cfg'->'inquilinos'),
    'cats', d->'cats',
    'serv', d->'serv',
    'prod', d->'prod',
    'turnosCfg', d->'turnosCfg',
    'resenas', (select coalesce(jsonb_agg(r), '[]'::jsonb)
                from jsonb_array_elements(coalesce(d->'resenas','[]'::jsonb)) r
                where coalesce((r->>'aprobada')::boolean, false))
  );
end $$;
grant execute on function public.estetica_publica(text) to anon, authenticated;

-- 3) Público: el cliente pide un turno (sin login) ----------------------
create or replace function public.estetica_agregar_turno(p_codigo text, p_turno jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  update public.estetica_backups
     set datos = jsonb_set(datos, '{turnos}',
           coalesce(datos->'turnos', '[]'::jsonb) || jsonb_build_array(p_turno)),
         updated_at = now()
   where tenant_id = p_codigo;
  if not found then return jsonb_build_object('ok', false, 'error', 'sin_local'); end if;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.estetica_agregar_turno(text, jsonb) to anon, authenticated;

-- 3b) Público: el cliente deja una opinión (queda PENDIENTE de aprobar) ---
create or replace function public.estetica_agregar_resena(p_codigo text, p_resena jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  update public.estetica_backups
     set datos = jsonb_set(datos, '{resenas}',
           coalesce(datos->'resenas', '[]'::jsonb)
             || jsonb_build_array((p_resena - 'aprobada') || jsonb_build_object('aprobada', false))),
         updated_at = now()
   where tenant_id = p_codigo;
  if not found then return jsonb_build_object('ok', false, 'error', 'sin_local'); end if;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.estetica_agregar_resena(text, jsonb) to anon, authenticated;

-- 4) Colaboradores: verificar (sin login) y unirse (con login) ----------
--    El colaborador entra solo si el dueño ya lo aceptó (estado = aprobado).
create or replace function public.estetica_verificar_colab(p_codigo text, p_usuario text, p_pass text)
returns boolean language plpgsql security definer set search_path = public as $$
declare ok boolean;
begin
  select exists (
    select 1 from public.estetica_backups b,
      jsonb_array_elements(coalesce(b.datos->'colabs','[]'::jsonb)) c
    where b.tenant_id = p_codigo
      and lower(c->>'usuario') = lower(p_usuario)
      and c->>'pass' = p_pass
      and coalesce(c->>'estado','') = 'aprobado'
  ) into ok;
  return coalesce(ok, false);
end $$;
grant execute on function public.estetica_verificar_colab(text, text, text) to anon, authenticated;

create or replace function public.estetica_unir_colab(p_codigo text, p_usuario text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  insert into public.tl_miembros (user_id, tenant_id, rol, usuario)
    values (auth.uid(), p_codigo, 'colab', p_usuario)
  on conflict (user_id, tenant_id) do update set rol = 'colab', usuario = excluded.usuario;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.estetica_unir_colab(text, text) to authenticated;
