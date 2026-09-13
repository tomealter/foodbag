create function get_household_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select household_id from public.profiles where id = auth.uid();
$$;

alter table households enable row level security;
alter table profiles enable row level security;

create policy "users can view their own household"
on households
for select
using (households.id = get_household_id());

create policy "household members are visible to household"
on profiles
for select
using (profiles.household_id = get_household_id());
