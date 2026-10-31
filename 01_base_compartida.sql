-- =====================================================================
--  GASOLEROS METROPOL · base compartida v1
--  Pegar TODO este archivo en Supabase > SQL Editor > New query > Run.
--  Se puede volver a correr sin romper nada (usa "if not exists" / "or replace").
-- =====================================================================

-- ---------- reloj (un solo lugar; los clientes no pueden cambiarlo) ----------
create or replace function public._ahora() returns timestamptz
language sql stable as $$ select now() $$;
revoke all on function public._ahora() from public, anon, authenticated;

-- ---------- PERFILES (una fila por persona que se registra) ----------
create table if not exists public.perfiles (
  id      uuid primary key references auth.users(id) on delete cascade,
  legajo  text not null unique check (legajo ~ '^[0-9]{3,8}$'),
  nombre  text not null default '',
  rol     text not null default 'usuario' check (rol in ('admin','usuario')),
  activo  boolean not null default false,          -- false = pendiente de aprobación
  creado  timestamptz not null default now()
);
alter table public.perfiles enable row level security;

-- ---------- AUDITORÍA (registro de quién hizo qué; nadie lo puede editar ni borrar) ----------
create table if not exists public.auditoria (
  id          bigint generated always as identity primary key,
  ts          timestamptz not null default now(),
  user_id     uuid,
  legajo      text,
  accion      text not null,
  tabla       text not null,
  registro_id text,
  antes       jsonb,
  despues     jsonb,
  detalle     text
);
create index if not exists auditoria_ts_idx on public.auditoria (ts desc);
alter table public.auditoria enable row level security;

create or replace function public.auditoria_inmutable() returns trigger
language plpgsql as $$
begin
  raise exception 'El registro de auditoría no se puede modificar ni borrar';
end $$;
drop trigger if exists auditoria_no_update on public.auditoria;
create trigger auditoria_no_update before update or delete on public.auditoria
  for each row execute function public.auditoria_inmutable();
drop trigger if exists auditoria_no_truncate on public.auditoria;
create trigger auditoria_no_truncate before truncate on public.auditoria
  for each statement execute function public.auditoria_inmutable();

-- ---------- funciones de ayuda ----------
create or replace function public.es_activo(uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select activo from public.perfiles where id = uid), false)
$$;

create or replace function public.es_admin(uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select activo and rol = 'admin' from public.perfiles where id = uid), false)
$$;

create or replace function public.legajo_de(uid uuid) returns text
language sql stable security definer set search_path = public as $$
  select legajo from public.perfiles where id = uid
$$;

-- ---------- TURNOS ("En mi turno") ----------
create table if not exists public.turnos (
  id        bigint generated always as identity primary key,
  user_id   uuid not null references public.perfiles(id),
  legajo    text not null,
  turno     text not null check (turno in ('TM','TT','TN')),
  inicio    timestamptz not null default now(),
  fin_prog  timestamptz not null,        -- hora en que el turno se cierra solo
  fin       timestamptz                  -- hora en que lo cerró la persona (si lo hizo)
);
create index if not exists turnos_user_idx on public.turnos (user_id, inicio desc);
alter table public.turnos enable row level security;

-- ¿está la persona en turno ahora?
create or replace function public.en_turno(uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.turnos
    where user_id = uid and fin is null and public._ahora() < fin_prog
  ) and public.es_activo(uid)
$$;

-- ¿tenía turno en ese momento? (para subir cargas hechas sin señal)
create or replace function public.tenia_turno(uid uuid, ts timestamptz) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.turnos
    where user_id = uid
      and ts >= inicio - interval '10 minutes'
      and ts <  least(coalesce(fin, fin_prog), fin_prog) + interval '10 minutes'
  ) and public.es_activo(uid)
$$;

-- Turnos: TM 06-14, TT 14-19, TN 19-06 (hora de Argentina). Se puede entrar una hora antes.
create or replace function public.iniciar_turno(p_turno text) returns public.turnos
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  zona constant text := 'America/Argentina/Buenos_Aires';
  loc timestamp := public._ahora() at time zone zona;
  t time := loc::time;
  fin_loc timestamp;
  r public.turnos;
begin
  if uid is null or not public.es_activo(uid) then
    raise exception 'Tu usuario todavía no está habilitado';
  end if;
  if    p_turno = 'TM' and t >= time '05:00' and t < time '14:00' then fin_loc := date_trunc('day', loc) + interval '14 hours';
  elsif p_turno = 'TT' and t >= time '13:00' and t < time '19:00' then fin_loc := date_trunc('day', loc) + interval '19 hours';
  elsif p_turno = 'TN' and t >= time '18:00'                      then fin_loc := date_trunc('day', loc) + interval '30 hours';
  elsif p_turno = 'TN' and t <  time '06:00'                      then fin_loc := date_trunc('day', loc) + interval '6 hours';
  else
    raise exception 'Ahora no corresponde iniciar el turno %', p_turno;
  end if;

  update public.turnos set fin = public._ahora() where user_id = uid and fin is null;

  insert into public.turnos (user_id, legajo, turno, inicio, fin_prog)
  values (uid, public.legajo_de(uid), p_turno, public._ahora(), fin_loc at time zone zona)
  returning * into r;

  insert into public.auditoria (user_id, legajo, accion, tabla, registro_id, despues)
  values (uid, r.legajo, 'INICIO_TURNO', 'turnos', r.id::text, to_jsonb(r));
  return r;
end $$;

create or replace function public.terminar_turno() returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int;
begin
  if uid is null then raise exception 'Sin sesión'; end if;
  update public.turnos set fin = public._ahora() where user_id = uid and fin is null;
  get diagnostics n = row_count;
  if n > 0 then
    insert into public.auditoria (user_id, legajo, accion, tabla)
    values (uid, public.legajo_de(uid), 'FIN_TURNO', 'turnos');
  end if;
end $$;

-- ¿quién está en turno ahora? (lo ven todos los usuarios habilitados)
create or replace function public.quien_en_turno()
returns table (legajo text, nombre text, turno text, inicio timestamptz, fin_prog timestamptz)
language sql stable security definer set search_path = public as $$
  select t.legajo, p.nombre, t.turno, t.inicio, t.fin_prog
  from public.turnos t join public.perfiles p on p.id = t.user_id
  where public.es_activo(auth.uid()) and t.fin is null and public._ahora() < t.fin_prog
  order by t.inicio
$$;

-- ---------- CARGAS (la planilla compartida) ----------
create table if not exists public.cargas (
  id          uuid primary key default gen_random_uuid(),
  interno     text not null check (interno ~ '^[0-9]{4}$'),
  comb        numeric not null default 0 check (comb  >= 0 and comb  <= 1500),
  aceite      numeric not null default 0 check (aceite >= 0 and aceite <= 500),
  urea        numeric not null default 0 check (urea   >= 0 and urea   <= 500),
  refr        numeric not null default 0 check (refr   >= 0 and refr   <= 500),
  obs         text not null default '',
  creado      timestamptz not null default now(),   -- hora de la carga (del celular si estaba sin señal)
  registrado  timestamptz not null default now(),   -- hora en que llegó al servidor
  user_id     uuid not null,
  legajo      text not null,
  editado_por text,
  editado_en  timestamptz,
  borrado     boolean not null default false
);
create index if not exists cargas_creado_idx on public.cargas (creado desc);
create index if not exists cargas_interno_idx on public.cargas (interno, creado desc);
alter table public.cargas enable row level security;

create or replace function public.cargas_antes() returns trigger
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if tg_op = 'INSERT' then
    new.user_id    := uid;                               -- no se puede falsear quién carga
    new.legajo     := public.legajo_de(uid);
    new.registrado := public._ahora();
    if new.creado is null or new.creado > public._ahora() + interval '5 minutes'
       or new.creado < public._ahora() - interval '3 days' then
      new.creado := public._ahora();
    end if;
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
drop trigger if exists cargas_antes on public.cargas;
create trigger cargas_antes before insert or update on public.cargas
  for each row execute function public.cargas_antes();

create or replace function public.cargas_auditar() returns trigger
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  insert into public.auditoria (user_id, legajo, accion, tabla, registro_id, antes, despues)
  values (
    uid, coalesce(public.legajo_de(uid), 'sistema'),
    case when tg_op = 'INSERT' then 'ALTA'
         when new.borrado and not old.borrado then 'BORRADO'
         else 'MODIFICACION' end,
    'cargas', new.id::text,
    case when tg_op = 'UPDATE' then to_jsonb(old) end,
    to_jsonb(new));
  return new;
end $$;
drop trigger if exists cargas_auditar on public.cargas;
create trigger cargas_auditar after insert or update on public.cargas
  for each row execute function public.cargas_auditar();

-- ---------- ALTA DE USUARIOS ----------
-- Cuando alguien se registra (legajo + contraseña) se crea su perfil.
-- La PRIMERA persona que se registra queda como administradora y habilitada.
-- Las siguientes quedan "pendientes" hasta que un administrador las apruebe.
create or replace function public.nuevo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  leg text := coalesce(new.raw_user_meta_data->>'legajo', '');
  primero boolean;
begin
  if leg !~ '^[0-9]{3,8}$' then raise exception 'Legajo inválido'; end if;
  if lower(new.email) <> leg || '@gasoleros.app' then raise exception 'Datos de registro inconsistentes'; end if;
  select not exists (select 1 from public.perfiles) into primero;
  insert into public.perfiles (id, legajo, nombre, rol, activo)
  values (new.id, leg, left(coalesce(new.raw_user_meta_data->>'nombre', ''), 60),
          case when primero then 'admin' else 'usuario' end, primero);
  insert into public.auditoria (user_id, legajo, accion, tabla, registro_id, detalle)
  values (new.id, leg, 'ALTA_USUARIO', 'perfiles', new.id::text,
          case when primero then 'primer usuario: administrador' else 'pendiente de aprobación' end);
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.nuevo_usuario();

-- Administración (solo administradores)
create or replace function public.admin_set_usuario(p_id uuid, p_activo boolean, p_rol text) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); antes public.perfiles; despues public.perfiles;
begin
  if not public.es_admin(uid) then raise exception 'Solo administradores'; end if;
  if p_rol not in ('admin','usuario') then raise exception 'Rol inválido'; end if;
  if p_id = uid then raise exception 'No podés cambiar tu propio estado o rol'; end if;
  select * into antes from public.perfiles where id = p_id;
  if not found then raise exception 'Usuario inexistente'; end if;
  update public.perfiles set activo = p_activo, rol = p_rol where id = p_id returning * into despues;
  if not p_activo then
    update public.turnos set fin = public._ahora() where user_id = p_id and fin is null;
  end if;
  insert into public.auditoria (user_id, legajo, accion, tabla, registro_id, antes, despues)
  values (uid, public.legajo_de(uid), 'CAMBIO_USUARIO', 'perfiles', p_id::text, to_jsonb(antes), to_jsonb(despues));
end $$;

-- ---------- REGLAS DE ACCESO (RLS) ----------
drop policy if exists perfiles_ver on public.perfiles;
create policy perfiles_ver on public.perfiles for select to authenticated
  using (id = auth.uid() or public.es_admin(auth.uid()) or (activo and public.es_activo(auth.uid())));

drop policy if exists turnos_ver on public.turnos;
create policy turnos_ver on public.turnos for select to authenticated
  using (public.es_activo(auth.uid()));

drop policy if exists auditoria_ver on public.auditoria;
create policy auditoria_ver on public.auditoria for select to authenticated
  using (public.es_activo(auth.uid()));

drop policy if exists cargas_ver on public.cargas;
create policy cargas_ver on public.cargas for select to authenticated
  using (public.es_activo(auth.uid()));

drop policy if exists cargas_alta on public.cargas;
create policy cargas_alta on public.cargas for insert to authenticated
  with check (public.tenia_turno(auth.uid(), creado));

drop policy if exists cargas_cambio on public.cargas;
create policy cargas_cambio on public.cargas for update to authenticated
  using (public.en_turno(auth.uid())) with check (public.en_turno(auth.uid()));
-- (no hay política de borrado: las cargas nunca se borran de verdad, solo se marcan "borrado")

-- ---------- PERMISOS ----------
revoke all on public.perfiles, public.turnos, public.cargas, public.auditoria from anon, authenticated;
grant select on public.perfiles, public.turnos, public.auditoria to authenticated;
grant select, insert, update on public.cargas to authenticated;

revoke all on function public.es_activo(uuid), public.es_admin(uuid), public.legajo_de(uuid),
  public.en_turno(uuid), public.tenia_turno(uuid, timestamptz),
  public.iniciar_turno(text), public.terminar_turno(), public.quien_en_turno(),
  public.admin_set_usuario(uuid, boolean, text) from public, anon;
grant execute on function public.es_activo(uuid), public.es_admin(uuid), public.legajo_de(uuid),
  public.en_turno(uuid), public.tenia_turno(uuid, timestamptz),
  public.iniciar_turno(text), public.terminar_turno(), public.quien_en_turno(),
  public.admin_set_usuario(uuid, boolean, text) to authenticated;

-- ---------- funciones internas (solo las usa la base, no se pueden llamar desde la app) ----------
revoke all on function public.nuevo_usuario(), public.cargas_antes(), public.cargas_auditar(),
  public.auditoria_inmutable() from public, anon, authenticated;

-- ---------- TIEMPO REAL ----------
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime add table public.cargas;  exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.turnos;  exception when duplicate_object then null; end;
  end if;
end $$;
