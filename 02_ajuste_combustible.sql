-- AJUSTE: el combustible se anota como lo muestra el surtidor (44198 = 44,198 L), hasta 6 cifras.
-- Pegar en Supabase > SQL Editor > Run. Se puede correr más de una vez.
alter table public.cargas drop constraint if exists cargas_comb_check;
alter table public.cargas add constraint cargas_comb_check check (comb >= 0 and comb <= 999999);
