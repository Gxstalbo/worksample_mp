-- =====================================================================
-- REACTIVACIÓN ESPONTÁNEA por día de inactividad — Mercado Pago Chile
-- Enfoque: cohorte de seguimiento completo (sin censura) -> conteo directo.
-- Esto es un ejemplo, no utiliza datos reales ni buscamos sacar conclusiones a través de este ejercicio. 
-- También es una versión simplificada para que puedan corrobar el conocimiento en SQL no para deployar una solución.
-- =====================================================================
DECLARE fecha_corte DATE DEFAULT (
  SELECT MAX(fecha_transaccion)
  FROM `meli-bi-data.whowner.mp_transacciones_app`
  WHERE site_id = 'MLC'
);
DECLARE horizonte INT64 DEFAULT 90;            -- ventana de observación = 90 días

WITH
-- 1) Un registro por usuario-DÍA activo (colapsa varias tx del mismo día).
dias_activos AS (
  SELECT DISTINCT cust_id, fecha_transaccion AS dia_activo
  FROM `meli-bi-data.whowner.mp_transacciones_app`
  WHERE site_id = 'MLC' AND fecha_transaccion IS NOT NULL
),

-- 2) Gap de inactividad: días hasta la siguiente transacción del usuario.
spells AS (
  SELECT
    dia_activo,
    DATE_DIFF(
      LEAD(dia_activo) OVER (PARTITION BY cust_id ORDER BY dia_activo),
      dia_activo, DAY
    ) AS gap                                   -- NULL si no hay próxima transacción
  FROM dias_activos
),

-- 3) COHORTE DE SEGUIMIENTO COMPLETO  <-- el corazón del enfoque.
--    Solo spells cuyo inicio quedó >= 90 días ANTES del corte: de esos vimos
--    su ventana de 90 días entera, así que su resultado es definitivo
--    dia_react = día en que volvió, si fue dentro de 90; NULL = no volvió.
--    esto debido a que necesitamos seguir el ciclo de vida completo del cliente para estudiar su comportmaiento
obs AS (
  SELECT IF(gap BETWEEN 1 AND horizonte, gap, NULL) AS dia_react
  FROM spells
  WHERE dia_activo <= DATE_SUB(fecha_corte, INTERVAL horizonte DAY)
),

-- 4) Reactivaciones por día + eje 1..90.
-- Consideramos hasta el día 90 porque de lo contrario entra en campaña de activación. 
react_dia AS (
  SELECT dia_react AS d, COUNT(*) AS n
  FROM obs
  WHERE dia_react IS NOT NULL
  GROUP BY dia_react
),
eje AS (SELECT dia FROM UNNEST(GENERATE_ARRAY(1, horizonte)) AS dia)

-- 5) Curva = reactivaciones ACUMULADAS hasta el día d ÷ total de spells.
--    supervivencia (sigue inactivo) = 1 − reactivación.
-- la intención de este chunk de código es generar una view que permita generar la gráfica del worksample 
SELECT
  e.dia AS dia_inactividad,
  (SELECT COUNT(*) FROM obs) AS total_spells,
  SUM(COALESCE(r.n, 0)) OVER (ORDER BY e.dia) AS reactivaron_hasta_d,
  ROUND(SUM(COALESCE(r.n,0)) OVER (ORDER BY e.dia)
        / (SELECT COUNT(*) FROM obs), 5) AS reactivacion_espontanea,
  ROUND(1 - SUM(COALESCE(r.n,0)) OVER (ORDER BY e.dia)
        / (SELECT COUNT(*) FROM obs), 5) AS supervivencia
FROM eje e
LEFT JOIN react_dia r ON r.d = e.dia
ORDER BY e.dia;