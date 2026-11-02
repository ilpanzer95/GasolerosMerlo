-- CONTROL DE PLAYA COMPARTIDO EN TIEMPO REAL
-- Solo escribe quien tiene el turno abierto (lo exige la base). Todos los aprobados ven los cambios al instante.
-- Pegar en Supabase > SQL Editor > Run. Se puede correr más de una vez.
create table if not exists public.playa (
  interno     text primary key,
  linea       text not null default 'Sin línea',
  st          text not null default '' check (st in ('','C','F','S')),
  loc         text check (loc in ('T','P')),
  nuevo       boolean not null default false,
  baja        boolean not null default false,
  ts          bigint,
  legajo      text,
  actualizado timestamptz not null default now()
);

alter table public.playa enable row level security;
grant select, insert, update on public.playa to authenticated;

drop policy if exists playa_ver on public.playa;
create policy playa_ver on public.playa for select to authenticated
  using (public.es_activo(auth.uid()));

drop policy if exists playa_alta on public.playa;
create policy playa_alta on public.playa for insert to authenticated
  with check (public.tenia_turno(auth.uid(), public._ahora()));

drop policy if exists playa_mod on public.playa;
create policy playa_mod on public.playa for update to authenticated
  using (public.tenia_turno(auth.uid(), public._ahora()))
  with check (public.tenia_turno(auth.uid(), public._ahora()));
-- (sin política de borrado: nadie puede borrar filas; las bajas se marcan con baja = true)

create or replace function public.playa_antes() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.legajo      := public.legajo_de(auth.uid());   -- no se puede falsear quién anota
  new.actualizado := public._ahora();                 -- siempre la hora del servidor
  return new;
end $$;
drop trigger if exists playa_antes on public.playa;
create trigger playa_antes before insert or update on public.playa
  for each row execute function public.playa_antes();

-- tiempo real
do $$ begin
  alter publication supabase_realtime add table public.playa;
exception when duplicate_object then null; end $$;
