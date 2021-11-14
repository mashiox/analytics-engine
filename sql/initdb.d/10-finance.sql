--
-- Create finance database tables and views
--

\c finance

--
-- equities base table
--
create table equities (
	id uuid default gen_random_uuid() primary key,
	symbol varchar(36) not null,
	ts_create timestamp with time zone default now() not null,
	price numeric(16,4),
	meta jsonb
);

--
-- Exponential Moving Average
-- @see https://stackoverflow.com/a/8879118/1754679
--
create or replace function ema_func(state numeric, inval numeric, alpha numeric)
  returns numeric
  language sql as $$
select case
       when $1 is null then $2
       else $3 * $2 + (1-$3) * $1
       end
$$;
create aggregate ema(numeric, numeric) (sfunc = ema_func, stype = numeric);


