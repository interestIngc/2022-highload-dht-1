Было принято решение использовать consistent hashing для шардирования и хеш функцию xxhash. 
База данных нагружена на 1ГБ, получилось такое распределение по нодам:

```
veronika@MBP-Veronika dht % du -sh *
396M	node1
280M	node2
376M	node3
```
Видно, что ключи распределены почти равномерно на наших тестовых данных, но мы брали ключи как последовательные числа,
не факт что на реальных данных распределение получилось бы такое же.

```
veronika@MBP-Veronika anikina % wrk2 -t 8 -c 64 -d 3m -R 15000 -s lua/get.lua http://localhost:8080
Running 3m test @ http://localhost:8080
  8 threads and 64 connections
  Thread calibration: mean lat.: 134.832ms, rate sampling interval: 916ms
  Thread calibration: mean lat.: 134.870ms, rate sampling interval: 916ms
  Thread calibration: mean lat.: 134.255ms, rate sampling interval: 913ms
  Thread calibration: mean lat.: 135.079ms, rate sampling interval: 919ms
  Thread calibration: mean lat.: 134.915ms, rate sampling interval: 916ms
  Thread calibration: mean lat.: 134.403ms, rate sampling interval: 914ms
  Thread calibration: mean lat.: 135.323ms, rate sampling interval: 918ms
  Thread calibration: mean lat.: 134.695ms, rate sampling interval: 915ms
^C  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     1.14ms  636.27us   7.87ms   73.11%
    Req/Sec     1.88k     1.69     1.88k    92.65%
  390355 requests in 26.04s, 247.19MB read
Requests/sec:  14989.23
Transfer/sec:      9.49MB
```

Теперь база данных справляется с нагрузкой R = 15000, версия с использованием одной ноды выдерживала только R = 10000.
Однако, если попробовать большую нагрузку, например R = 20000, сервис уже "захлебывается".

Посмотрим на GET запросы:

```
veronika@MBP-Veronika anikina % wrk2 -t 8 -c 64 -d 3m -R 10000 -s lua/get.lua http://localhost:8080
Running 3m test @ http://localhost:8080
  8 threads and 64 connections
  Thread calibration: mean lat.: 0.995ms, rate sampling interval: 10ms
  Thread calibration: mean lat.: 0.997ms, rate sampling interval: 10ms
  Thread calibration: mean lat.: 0.993ms, rate sampling interval: 10ms
  Thread calibration: mean lat.: 0.998ms, rate sampling interval: 10ms
  Thread calibration: mean lat.: 0.991ms, rate sampling interval: 10ms
  Thread calibration: mean lat.: 0.998ms, rate sampling interval: 10ms
  Thread calibration: mean lat.: 0.990ms, rate sampling interval: 10ms
  Thread calibration: mean lat.: 1.010ms, rate sampling interval: 10ms
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     0.95ms  450.33us   5.66ms   66.25%
    Req/Sec     1.31k   104.54     1.78k    60.37%
  1799849 requests in 3.00m, 1.11GB read
Requests/sec:   9999.14
Transfer/sec:      6.33MB
```

Тут уже пришлось немного уменьшить и взять R = 10000, так же как в версии в одной нодой, на R = 15000 сервис не
"захлебывается", но latency составляет 156ms. 
Однако с R = 10000 latency меньше 1ms, что вполне хороший результат.

По результатам профилирования можно выделить следующее:

## PUT

### CPU
Работа с базой данных для ноды - координатора занимает 15% CPU, 13% уходит на сетевые запросы, 15% занимает 
работа клиента, 26% - синхронизация в executor service, остальное уходит на селекторы. 
По сравнению с версией без шардирования, меньше времени тратится 
на работу селекторов, но зато большой процент CPU уходит на проксирование запросов. Синхронизация потоков 
в executor service занимает такой же процент времени.

### ALLOC
14% аллокаций занимает работа с базой, 33% - работа с сетью, и 41% занимают селекторы.
По сравнению с прошлой версией, обращения к базе занимают намного меньше аллокаций, 14% vs 44%, но при этом большое 
число аллокаций занимает проксирование.

### LOCK
Почти все 100% блокировок уходят на HttpClient. 
В прошлой версии 78% локов были связаны с обращением к блокирующией очереди в threadPoolExecutor, теперь же они не 
заметны на фоне блокировок, связанных с работой клиента при проксировании запросов.

## GET

### CPU
Аналогично put запросам, работа с базой занимает 16%, 12% - сетевые запросы, 16% - работа клиента, 26% - синхронизация, 
остальное уходит на селекторы. Теперь разницы в потреблении CPU между put и get запросами почти нет за 
счет того, что большой процент занимают сетевые запросы.

Точно так же нет разницы для ALLOC и LOCK между put и get запросами, так как большой процент как аллокаций, так и 
блокировок занимает работа с сетью.

## ВЫВОДЫ

Использование хеш функции xxHash позволило добиться почти равномерного распределения ключей по нодам, 
однако наши ключи - последовательные числа, при использовании сервиса в production не факт, 
что получилось бы такое же распределение.

Большую часть и cpu, и alloc и lock занимает общение нод через http, в качестве оптимизации можно было бы взять
другой протокол с меньшим оверхедом. Возможно, даже использование более эффективной реализации http client бы
уже повысило производительность.