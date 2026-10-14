-- Crystamber usage. Run in the Supabase SQL editor, or ask the Council
-- "how's Crystamber usage?". Collectors = signed-up users; Nelsen is included.

-- Weekly active collectors, last 8 weeks [weeks start Monday, Jakarta dates].
select date_trunc('week', day)::date as week, count(distinct user_id) as active
from app_days
where day > current_date - 56
group by 1 order by 1;

-- Per collector: when they joined, days opened, last open, cards added in the last 7 days.
select p.username,
       (u.created_at at time zone 'Asia/Jakarta')::date as joined,
       (select count(*) from app_days d where d.user_id = u.id) as days_opened,
       (select max(day) from app_days d where d.user_id = u.id) as last_open,
       (select count(*) from user_sets s, jsonb_each_text(s.owned) o
         where s.user_id = u.id and o.value >= to_char(current_date - 7, 'YYYY-MM-DD')) as cards_added_7d
from auth.users u left join profiles p on p.id = u.id
order by last_open desc nulls last;
