--= УСТАНАВЛИВАЕМ СОЕДИНЕНИЕ И ВЫБРАЕМ СХЕМУ BOOKINGS =
SET search_path = bookings;

--Задание 1. В каких городах больше одного аэропорта?

--Вариант решения 1:

select city from airports
group by city 
having count(city) > 1
order by city;

--Вариант решения 2:

select a.airport_code as code,
 a.airport_name,
 a.city,
 a.longitude,
 a.latitude,
 a.timezone
from airports a
where a.city in (
 select aa.city
 from airports aa
 group by aa.city
 having count(*) > 1
 )
order by a.city, a.airport_code;


--Задание 2. В каких аэропортах есть рейсы, выполняемые самолетом с максимальной дальностью перелета?

select departure_airport, departure_airport_name 
from flights_v fv 
where fv.aircraft_code = (select a.aircraft_code from aircrafts a order by a."range" desc limit 1)
union
select arrival_airport, arrival_airport_name 
from flights_v fv 
where fv.aircraft_code = (select a.aircraft_code from aircrafts a order by a."range" desc limit 1);


--Задание 3. Вывести 10 рейсов с максимальным временем задержки вылета

select 
  actual_departure - scheduled_departure as departure_delay, 
  flight_no,  
  departure_airport 
from flights 
where actual_departure - scheduled_departure is not null
order by departure_delay desc
limit 10;


--Задание 4. Были ли брони, по которым не были получены посадочные талоны?

select b.book_ref, bp.boarding_no, bp.ticket_no  
from bookings b 
left join tickets t on b.book_ref = t.book_ref
left join boarding_passes bp on t.ticket_no = bp.ticket_no
where bp.boarding_no is null;


--Задание 5. Найдите количество свободных мест для каждого рейса, их % отношение к общему количеству мест в самолете.
--Добавьте столбец с накопительным итогом - суммарное накопление количества вывезенных пассажиров из каждого аэропорта на каждый день. 
--Т.е. в этом столбце должна отражаться накопительная сумма - сколько человек уже вылетело из данного аэропорта на этом или более ранних 
--рейсах в течении дня.

with cte as (
	select s.aircraft_code, count(s.seat_no) as "count", a.model
	from seats s
	join aircrafts a on a.aircraft_code = s.aircraft_code 
	group by s.aircraft_code, a.model
)
select 
  departure_airport, 
  actual_departure , 
  cte."count" - count(bp.seat_no)  as available_seats,
  (((cte."count" - count(bp.seat_no))::numeric / cte."count")::numeric(32,2)) * 100 as percentage_of_available_seats,
  sum(count(bp.seat_no)) over (partition by f.actual_departure::date, f.departure_airport order by f.actual_departure) as cumulative_total
from boarding_passes bp
join flights f on f.flight_id = bp.flight_id
join cte on cte.aircraft_code = f.aircraft_code 
group by f.flight_id, cte."count";


--Задание 6. Найдите процентное соотношение перелетов по типам самолетов от общего количества.
l
select model, (round("count"::numeric / (sum("count") over ()), 2) * 100) as percentage_of_total_number_of_flights
from(
	select count(flight_id) as "count", model
	from flights f 
	join aircrafts a on a.aircraft_code = f.aircraft_code
	group by model
) f;


--Задание 7. Были ли города, в которые можно  добраться бизнес - классом дешевле, чем эконом-классом в рамках перелета?

with cte_1 as (
	select distinct tf.flight_id, max(amount) as price_econom, fare_conditions 
	from ticket_flights tf
	where tf.fare_conditions = 'Economy'
	group by flight_id, fare_conditions 
	order by flight_id
) ,
 cte_2 as (
	select distinct tf.flight_id, min(amount) as price_business , fare_conditions 
	from ticket_flights tf
	where tf.fare_conditions = 'Business'
	group by flight_id, fare_conditions 
	order by flight_id
)
select a.city as city_of_arrival
from cte_1
join cte_2 on cte_2.flight_id = cte_1.flight_id
join flights f on f.flight_id = cte_1.flight_id
join airports a on a.airport_code = f.arrival_airport
where price_business < price_econom;


--Задание 8. Между какими городами нет прямых рейсов?

create view cities_v as
select v.departure_city, v.arrival_city
from flights_v v

select distinct a.city, a1.city
from airports a
cross join airports a1
where a.city != a1.city
  except
select c.departure_city, c.arrival_city
from cities_v c;


--Задание 9. Вычислите расстояние между аэропортами, связанными прямыми рейсами, сравните с допустимой максимальной дальностью перелетов в самолетах, 
--обслуживающих эти рейсы

with cte as (
	select f.departure_airport, dep.longitude, dep.latitude, f.arrival_airport, arr.longitude, arr.latitude,
	f.arrival_airport, f.aircraft_code,
	round(((acos((sind(dep.latitude)*sind(arr.latitude) + cosd(dep.latitude) * cosd(arr.latitude) * cosd((dep.longitude - arr.longitude))))) * 6371)::numeric, 2)
	as distance_airports ,
	f.flight_no,
	dep.airport_name as departure_airport_name,
	arr.airport_name as arrival_airport_name
	from 
	flights f,
	airports dep,
	airports arr
	where f.departure_airport = dep.airport_code and f.arrival_airport = arr.airport_code
)
select distinct cte.departure_airport_name, cte.arrival_airport_name, cte.distance_airports,
a.range as aircraft_flight_distance,
case
when range > distance_airports
then 'Полёт прошёл удачно'
else 'КРУШЕНИЕ САМОЛЁТА'
end result
from aircrafts a 
join cte on cte.aircraft_code = a.aircraft_code
