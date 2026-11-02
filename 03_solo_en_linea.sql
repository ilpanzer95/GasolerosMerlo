-- SOLO EN LÍNEA: la carga siempre lleva la hora del servidor y solo vale mientras el turno está abierto.
-- Ya no hay "cargas hechas sin señal que se suben después". Pegar en Supabase > SQL Editor > Run.
-- Se puede correr más de una vez.
create or replace function public.cargas_antes() returns trigger
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if tg_op = 'INSERT' then
    new.user_id    := uid;                               -- no se puede falsear quién carga
    new.legajo     := public.legajo_de(uid);
    new.registrado := public._ahora();
    new.creado     := public._ahora();                    -- siempre la hora del servidor
    new.editado_por := null; new.editado_en := null; new.borrado := false;
  else
    new.id         := old.id;
    new.user_id    := old.user_id;
    new.legajo     := old.legajo;
    new.creado     := old.creado;
    new.registrado := old.registrado;
    new.editado_por := coalesce(public.legajo_de(uid), 'sistema');
    new.editado_en  := public._ahora();
  end if;
  return new;
end $$;

create or replace function public.tenia_turno(uid uuid, ts timestamptz) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.turnos
    where user_id = uid
      and ts >= inicio
      and ts <  least(coalesce(fin, fin_prog), fin_prog)
  ) and public.es_activo(uid)
$$;
