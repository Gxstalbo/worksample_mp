with push_super_promo as (
select user_id, min(event_timestamp) as event_timestamp
from `meli-bi-data.WHOWNER.marketing_push_logs`
where campaign_id = 'QR_SUPER_PROMO'
and event_type in ('delivered','clicked') -- supongamos que delivered es válido porque se generó el push y el cliente pudo haberlo leído, además es una práctica común en las campañas comerciales 
and event_timestamp >= TIMESTAMP('2026-01-01 00:00:00') -- ultimo feriado en chile
group by all -- agrupamos por user_id porque el campaing_id es único es irrelevante, para cumplir con la regla de negocio #2 rescatamos el evento más antiguo en timestamp. Esto reduce el user_id a una única fila y es útil porque puedo hacer un inner join con mp_transactions sin duplicar valores indebidamente en mp_transactions
), mp_trans as (
select user_id, transaction_timestamp, amount, currency, date(transaction_timestamp) as transaction_date
from `meli-bi-data.WHOWNER.mp_transactions`
where status = 'approved'  
)

select sum(amount*usd_rate) as TOTAL_USD_TPV -- sumamos sum(amount*usd_rate) sin pais porque nos piden el TPV total, se lo contrario se puede trabajar con la agrupación que queremos pais / cliente / campaña / etc
from (
select t1.user_id as user_id, t1.transaction_date as transaction_date, t1.amount as amount, t1.currency as currency
from mp_trans t1
inner join push_super_promo t2 
on t1.user_id = t2.user_id
where TIMESTAMP_DIFF(t1.transaction_timestamp, t2.event_timestamp, HOUR) >= 24 -- filtramos que el registro es válido 24 horas después de la campaña para cumplir la regla #1.
) principal_table 
left join `meli-bi-data.WHOWNER.daily_fx_rates` t3 -- supongamos que t3 no tiene valores duplicados ni vacíos
on principal_table.transaction_date = t3.date
AND principal_table.currency = t3.currency

