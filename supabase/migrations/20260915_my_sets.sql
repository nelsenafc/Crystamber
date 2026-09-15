-- The sets each person collects, so their tabs only show those. Null means
-- they have not chosen yet, and the app asks on their next visit.
alter table public.profiles add column my_sets text[];
grant update (my_sets) on public.profiles to authenticated;
