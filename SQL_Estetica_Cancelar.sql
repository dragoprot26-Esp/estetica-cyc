-- ======================================================================
--  ESTÉTICA (Aurelia) — Cancelación de turno por el cliente (sin login)
--  Base compartida: pcxlhgdpxfuybzfsquem
--  El cliente, desde la página pública, ingresa su código y cancela.
--  Marca el turno como estado = 'cancelado' (el dueño lo ve en el panel).
--  Correlo COMPLETO en el SQL Editor de Supabase (se puede repetir).
-- ======================================================================

create or replace function public.estetica_cancelar_turno(p_codigo text, p_cod_turno text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare arr jsonb; nuevo jsonb; existe boolean;
begin
  select datos->'turnos' into arr from public.estetica_backups where tenant_id = p_codigo;
  if arr is null then return jsonb_build_object('ok', false, 'error', 'sin_local'); end if;

  select exists (
    select 1 from jsonb_array_elements(arr) e
    where upper(e->>'codigo') = upper(p_cod_turno)
  ) into existe;
  if not existe then return jsonb_build_object('ok', false, 'error', 'sin_turno'); end if;

  select coalesce(jsonb_agg(
           case when upper(e->>'codigo') = upper(p_cod_turno)
                then e || jsonb_build_object('estado', 'cancelado')
                else e end
         ), '[]'::jsonb)
    into nuevo
    from jsonb_array_elements(arr) e;

  update public.estetica_backups
     set datos = jsonb_set(datos, '{turnos}', nuevo),
         updated_at = now()
   where tenant_id = p_codigo;

  return jsonb_build_object('ok', true);
end $$;

grant execute on function public.estetica_cancelar_turno(text, text) to anon, authenticated;
