**//Создание схемы raw_data//**
  
create schema raw_data;

**// Создание дочерней таблицы в схему raw_data//**
  
create table raw_data.sales (
id smallint,
auto varchar,
gasoline_consumption numeric(2, 1),
price numeric(9, 2),
date date,
person text,
phone varchar,
discount smallint,
brand_origin text
);

**//Копирование таблицы из csv //**
  
\copy raw_data.sales(id, auto, gasoline_consumption, price, date, person, phone, discount, brand_origin) from 'C:\temp\cars.csv' CSV header null as 'null';

**//Создание схемы //**
create schema car_shop;

**//Создание таблиц в схему car_shop//**

create table car_shop.persons (
id SERIAL primary key, /* уникальный id*/
person_id INT unique not null, /* РК для связи таблиц*/
person_name VARCHAR(100) not null, /*для оптимизации памяти выбрала не text, ограничение в 100 символов достаточно*/
phone VARCHAR(30) unique not null /*так как есть и символы и цифры взяла этот формат, ограничение в 30 символов достаточно для телефона*/
);

create table car_shop.colors (
id SERIAL primary key, /* уникальный id*/
color_id INT unique not null, /* РК для связи таблиц*/
color_name VARCHAR(30) unique not null /*для оптимизации памяти выбрала не text, ограничение в 30 символов достаточно*/
);

create table car_shop.brands (
id SERIAL primary key, /* уникальный id*/
brand_id INT unique not null, /* РК для связи таблиц*/
brand_name VARCHAR(30) unique not null, /*для оптимизации памяти выбрала не text, ограничение в 30 символов достаточно*/
brand_origin VARCHAR(30) /*для оптимизации памяти выбрала не text, ограничение в 30 символов достаточно*/
);

create table car_shop.models (
id SERIAL primary key, /* уникальный id*/
model_id INT unique not null, /* РК для связи таблиц*/
brand_id INT not null,
model_name VARCHAR(30) not null, /*для оптимизации памяти выбрала не text, ограничение в 30 символов достаточно, */
	/*не выставила уникальность, так как возможно будет одинаковое название модели у разных брендов с разным расходом топлива*/
gasoline_consumption NUMERIC(3, 1), /*выбрала этот вид, так как в таблице это дробные числа с одной цифрой после запятой, */
	/*ограничение 3 потому что расход с более чем 99.9литров предпологаю не возникнет*/
constraint fk_model_brand foreign key (brand_id) references car_shop.brands(brand_id)  /* связь с таблицей брендов*/
);

create table car_shop.deal_condithions (
id SERIAL primary key, /* уникальный id*/
deal_id INT unique not null, /* РК для связи таблиц*/
price numeric(10, 2) not null, /* цена это дробное число с максимум 2 символами после запятой */
date DATE not null, /* дата продажи это формат дата */
discount smallint DEFAULT 0 /* этот формат так как он по памяти экономнее чем int, также указала значение по умолчанию 0 */
);

**//Добавление данных в таблицы из таблицы raw_data.sales в таблицы схемы car_shop//**
  
insert into car_shop.colors (color_id, color_name)
select 
	row_number() over (order by color_name),
	color_name
from (
select distinct trim(split_part(auto, ',', 2)) as color_name
from raw_data.sales
) t
where color_name is not null and color_name != '';

insert into car_shop.brands (brand_id, brand_name, brand_origin)
select 
	row_number() over (order by brand_origin),
	brand_name,
	brand_origin
from (
select distinct trim(split_part(split_part(auto, ',', 1), ' ', 1)) as brand_name, 
brand_origin
from raw_data.sales
) t;

insert into car_shop.models (model_id, brand_id, model_name, gasoline_consumption)
select
	row_number() over (order by model_name),
	b.brand_id,
	t.model_name,
	t.gasoline_consumption
from (
	select distinct
		trim(split_part(split_part(auto, ',', 1), ' ', 1)) as brand_name,
		trim(REGEXP_replace(split_part(auto, ',', 1), '^[^\s]+\s*', '')) as model_name,
		AVG(gasoline_consumption) as gasoline_consumption
	from raw_data.sales
	group by 1, 2
) t
join car_shop.brands b on b.brand_name = t.brand_name;

insert into car_shop.persons (person_id, person_name, phone)
select 
	row_number() over (order by phone),
	person,
	phone
from (
	select distinct person, phone
	from raw_data.sales
) t;

insert into car_shop.deal_condithions (deal_id, price, date, discount)
select
	id,
	price,
	date,
	discount
from raw_data.sales;

**//При добавлении данных в таблицу car_shop.sales скрипт выполнялся, но данные не добавлялись. Погуглила в интеренете проверила на корректность. проверка показала, что данные в таблицах выше корректны(нет пробелов и т.д)
  решила сформировать дополнительные ячейки в таблице raw_data.sales которые будут формировать нужные ID из сформированных таблиц и их id //**

ALTER TABLE raw_data.sales ADD COLUMN IF NOT EXISTS tmp_person_id INT;
ALTER TABLE raw_data.sales ADD COLUMN IF NOT EXISTS tmp_model_id INT;
ALTER TABLE raw_data.sales ADD COLUMN IF NOT EXISTS tmp_color_id INT;

**// Здесь наполняю вновь созданные колонки данными //**
  
UPDATE raw_data.sales raw
SET tmp_person_id = p.person_id
FROM car_shop.persons p
WHERE p.person_name = raw.person AND p.phone = raw.phone;

UPDATE raw_data.sales raw
SET tmp_color_id = c.color_id
FROM car_shop.colors c
WHERE c.color_name = TRIM(SPLIT_PART(raw.auto, ',', 2));

UPDATE raw_data.sales raw
SET tmp_model_id = m.model_id
FROM car_shop.brands b
JOIN car_shop.models m ON m.brand_id = b.brand_id
WHERE b.brand_name = TRIM(SPLIT_PART(SPLIT_PART(raw.auto, ',', 1), ' ', 1))
  AND m.model_name = TRIM(REGEXP_REPLACE(SPLIT_PART(raw.auto, ',', 1), '^[^\s]+\s*', ''));

**// Теперь наполнение таблицы car_shop.sales выполнено //**
  
INSERT INTO car_shop.sales (id, person_id, model_id, color_id, deal_id)
SELECT 
    id,
    tmp_person_id,
    tmp_model_id,
    tmp_color_id,
    id -- deal_id равен id строки
FROM raw_data.sales;
	


**// Задания по таблице //*

  **// Задание 1 //*
  
select 
round(
	AVG(case when gasoline_consumption is null then 1.0 else 0.0 end)*100, 2) 
	as nulls_percentage_gasoline_consumption 
from car_shop.models;
 
**// Задание 2 //*
  
select 
	b.brand_name,
	EXTRACT(year from dc.date)::INT as year,
	round(avg(dc.price * (1-dc.discount / 100.0)), 2) as price_avg
from car_shop.sales s 
join car_shop.models m on m.model_id = s.model_id
join car_shop.brands b on b.brand_id = m.brand_id
join car_shop.deal_condithions dc on dc.deal_id = s.deal_id
group by
	b.brand_name,
	EXTRACT(year from dc.date)
order by 
	b.brand_name asc,
	year asc;

 **// Задание 3 //*

select 
	extract(month from dc.date):: int as month,
	extract(year from dc.date):: int as year,
	round(AVG(dc.price * (1- dc.discount / 100.0)), 2) as price_avg
from car_shop.sales s
join car_shop.deal_condithions dc on dc.deal_id = s.deal_id
where extract(year from dc.date) = 2022
group by
	extract(month from dc.date),
	extract(year from dc.date)
order by 
	month asc;

 **// Задание 4 //*

select 
	p.person_name as person,
	STRING_agg(b.brand_name || ' ' || m.model_name, ', ') as cars
from car_shop.sales s
join car_shop.persons p using (person_id)
join car_shop.models m using (model_id)
join car_shop.brands b using (brand_id)
group by
	p.person_name
order by
	person asc;

 **// Задание 5 //*

select 
	b.brand_origin,
	ROUND(MAX(dc.price / (1- dc.discount / 100.0)), 2) as price_max,
	ROUND(MIN(dc.price / (1- dc.discount / 100.0)), 2) as price_min
from car_shop.sales s 
join car_shop.models m using (model_id)
join car_shop.brands b using (brand_id)
join car_shop.deal_condithions dc using (deal_id)
group by 
	b.brand_origin;

 **// Задание 6 //*
   
select 
	count(*) as persons_from_usa_count
from car_shop.persons p 
where phone like '+1%';
