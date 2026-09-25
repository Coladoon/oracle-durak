# ER-модель проекта «Дурак» на Oracle

## 1. Назначение модели

Модель данных хранит пользователей, параметры партий, состав игроков, экземпляры
карт, состояние раундов и стола, журнал событий, перемещения карт, Daily-раскладки
и результаты. Основная единица изоляции данных — партия `DURAK_GAME`.

В схеме используется 13 сущностей. Идентификаторы формируются общей
последовательностью `DURAK_ID_SEQ`. Составные ключи применяются там, где запись
имеет смысл только внутри партии: место игрока, карта партии, раунд и пара на
столе.

## 2. Сводный перечень сущностей

| Сущность | Назначение |
|---|---|
| `DURAK_PLAYER` | Участники игры и соответствие Oracle-пользователям. |
| `DURAK_CARD` | Справочник 52 карт с признаком принадлежности колоде 36. |
| `DURAK_DAILY` | Детерминированная конфигурация Daily на дату. |
| `DURAK_GAME` | Параметры, текущая фаза и итог партии. |
| `DURAK_GAME_PLAYER` | Участник конкретной партии, его место, статус и результат. |
| `DURAK_ACTIVE_SESSION` | Ограничение «одна активная партия на пользователя». |
| `DURAK_GAME_CARD` | Экземпляр карты в партии, её позиция и текущая зона. |
| `DURAK_ROUND` | Атакующий, защитник, лимиты и результат одного раунда. |
| `DURAK_TABLE_PAIR` | Пара карт «атака — защита» на игровом столе. |
| `DURAK_EVENT` | Полный протокол действий и изменений состояния партии. |
| `DURAK_CARD_MOVE` | Детализированное перемещение карты, связанное с событием. |
| `DURAK_ERROR` | Автономный журнал отклонённых операций и ошибок. |
| `DURAK_DAILY_RESULT` | Результат участника в Daily-партии. |

## 3. Описание сущностей

### 3.1. DURAK_PLAYER — игрок

Хранит постоянную запись участника. Для человека `DB_USERNAME` содержит имя
Oracle-пользователя; системные записи применяются внутренними тестами.

| Поле | Тип | Ключ | Назначение |
|---|---|---|---|
| `PLAYER_ID` | `NUMBER(19)` | PK | Идентификатор игрока. |
| `DB_USERNAME` | `VARCHAR2(128)` | UQ | Имя Oracle-пользователя в верхнем регистре. |
| `DISPLAY_NAME` | `VARCHAR2(100)` |  | Отображаемое имя. |
| `PLAYER_TYPE` | `VARCHAR2(10)` |  | `HUMAN` или `SYSTEM`. |
| `LOCALE_CODE` | `VARCHAR2(20)` |  | Локаль сообщений. |
| `TIME_ZONE_NAME` | `VARCHAR2(64)` |  | Часовой пояс игрока. |
| `CREATED_AT` | `TIMESTAMP WITH TIME ZONE` |  | Дата регистрации. |

### 3.2. DURAK_CARD — карта

Нормативный справочник карт. Каждая комбинация ранга и масти уникальна.

| Поле | Тип | Ключ | Назначение |
|---|---|---|---|
| `CARD_ID` | `NUMBER(3)` | PK | Идентификатор карты. |
| `CARD_CODE` | `VARCHAR2(3)` | UQ | Код: `6C`, `10H`, `AS`. |
| `RANK_CODE` | `VARCHAR2(2)` |  | Обозначение ранга. |
| `RANK_VALUE` | `NUMBER(2)` | UQ* | Числовой приоритет ранга 2–14. |
| `SUIT_CODE` | `CHAR(1)` | UQ* | Масть `C`, `D`, `H` или `S`. |
| `INCLUDED_IN_36` | `CHAR(1)` |  | Входит ли карта в короткую колоду. |
| `SORT_ORDER` | `NUMBER(3)` | UQ | Порядок отображения. |

`RANK_VALUE` и `SUIT_CODE` образуют составное уникальное ограничение.

### 3.3. DURAK_DAILY — Daily-конфигурация

Определяет единый seed и набор правил для раскладки дня. Комбинация даты,
размера колоды, варианта, первого хода и версии правил уникальна.

| Поле | Тип | Ключ | Назначение |
|---|---|---|---|
| `DAILY_ID` | `NUMBER(19)` | PK | Идентификатор конфигурации. |
| `DAILY_DATE` | `DATE` | UQ* | Календарная дата без времени. |
| `DECK_SIZE` | `NUMBER(2)` | UQ* | 36 или 52 карты. |
| `GAME_VARIANT` | `VARCHAR2(12)` | UQ* | `PODKIDNOY` или `PEREVODNOY`. |
| `FIRST_MOVE_MODE` | `VARCHAR2(20)` | UQ* | `LOWEST_TRUMP` или `SEEDED_RANDOM`. |
| `SEED_TEXT` | `VARCHAR2(128)` |  | Исходное значение seed. |
| `CONFIG_HASH` | `RAW(32)` |  | Контрольный хеш конфигурации. |
| `RULES_VERSION` | `VARCHAR2(20)` | UQ* | Версия правил Daily. |
| `CREATED_AT` | `TIMESTAMP WITH TIME ZONE` |  | Дата создания. |

### 3.4. DURAK_GAME — партия

Центральная сущность. Содержит неизменяемые параметры партии, текущую фазу,
роли игроков, таймеры, optimistic-lock версию и итог завершения.

| Поле | Тип | Ключ | Назначение |
|---|---|---|---|
| `GAME_ID` | `NUMBER(19)` | PK | Идентификатор партии. |
| `CREATED_BY_PLAYER_ID` | `NUMBER(19)` | FK | Создатель → `DURAK_PLAYER`. |
| `DAILY_ID` | `NUMBER(19)` | FK | Daily-конфигурация, если партия Daily. |
| `DECK_SIZE` | `NUMBER(2)` |  | Размер колоды. |
| `GAME_VARIANT` | `VARCHAR2(12)` |  | Подкидной или переводной вариант. |
| `FIRST_MOVE_MODE` | `VARCHAR2(20)` |  | Правило выбора первого хода. |
| `TARGET_HAND_SIZE` | `NUMBER(2)` |  | Целевой размер руки, обычно 6. |
| `MAX_PAIRS` | `NUMBER(2)` |  | Предельное число пар на столе. |
| `ALLOW_THROW_AFTER_TAKE` | `CHAR(1)` |  | Разрешение подбрасывать после объявления взятия. |
| `LIMIT_BY_DEFENDER_HAND` | `CHAR(1)` |  | Ограничение стола рукой защитника. |
| `TURN_TIMEOUT_SEC` | `NUMBER(6)` |  | Лимит игрового действия. |
| `IDLE_TIMEOUT_MIN` | `NUMBER(6)` |  | Лимит простоя партии. |
| `SEED_TEXT` | `VARCHAR2(128)` |  | Seed раздачи. |
| `SEED_HASH` | `RAW(32)` |  | Хеш seed. |
| `SHUFFLE_VERSION` | `VARCHAR2(20)` |  | Версия алгоритма перемешивания. |
| `GAME_STATUS` | `VARCHAR2(12)` |  | `LOBBY`, `ACTIVE`, `FINISHED`, `CANCELLED`, `EXPIRED`. |
| `PHASE` | `VARCHAR2(20)` |  | Текущий этап игрового автомата. |
| `TRUMP_SUIT` | `CHAR(1)` |  | Козырная масть. |
| `TRUMP_CARD_ID` | `NUMBER(3)` | FK | Открытая карта козыря → `DURAK_CARD`. |
| `CURRENT_ROUND_NO` | `NUMBER(10)` |  | Текущий номер раунда. |
| `ATTACKER_SEAT_NO` | `NUMBER(1)` |  | Место атакующего. |
| `DEFENDER_SEAT_NO` | `NUMBER(1)` |  | Место защитника. |
| `CURRENT_ACTOR_SEAT_NO` | `NUMBER(1)` |  | Игрок, от которого ожидается действие. |
| `VERSION_NO` | `NUMBER(19)` |  | Версия состояния для защиты от гонок. |
| `NEXT_EVENT_NO` | `NUMBER(19)` |  | Следующий номер события. |
| `ACTION_DEADLINE_AT` | `TIMESTAMP WITH TIME ZONE` |  | Момент срабатывания таймера хода. |
| `LAST_ACTIVITY_AT` | `TIMESTAMP WITH TIME ZONE` |  | Последняя активность. |
| `CREATED_AT` | `TIMESTAMP WITH TIME ZONE` |  | Создание партии. |
| `STARTED_AT` | `TIMESTAMP WITH TIME ZONE` |  | Начало раздачи. |
| `FINISHED_AT` | `TIMESTAMP WITH TIME ZONE` |  | Завершение партии. |
| `FOOL_SEAT_NO` | `NUMBER(1)` |  | Место проигравшего. |
| `FINISH_REASON` | `VARCHAR2(40)` |  | Причина завершения. |

### 3.5. DURAK_GAME_PLAYER — участник партии

Ассоциативная сущность между игроком и партией. Один игрок может участвовать в
разных партиях, но в пределах партии занимает ровно одно место.

| Поле | Тип | Ключ | Назначение |
|---|---|---|---|
| `GAME_ID` | `NUMBER(19)` | PK, FK | Партия → `DURAK_GAME`. |
| `SEAT_NO` | `NUMBER(1)` | PK | Место 1–6. |
| `PLAYER_ID` | `NUMBER(19)` | FK, UQ* | Игрок → `DURAK_PLAYER`. |
| `PLAYER_STATUS` | `VARCHAR2(10)` |  | `WAITING`, `ACTIVE`, `OUT`, `FOOL`, `LEFT`. |
| `IS_CREATOR` | `CHAR(1)` |  | Признак создателя партии. |
| `HAND_COUNT` | `NUMBER(3)` |  | Текущее число карт в руке. |
| `FINISH_PLACE` | `NUMBER(1)` |  | Порядок выхода. |
| `RESULT_CODE` | `VARCHAR2(12)` |  | `WIN`, `LOSS`, `DRAW`, `ABANDONED`. |
| `JOINED_AT` | `TIMESTAMP WITH TIME ZONE` |  | Время подключения. |
| `EXITED_AT` | `TIMESTAMP WITH TIME ZONE` |  | Время выхода. |

### 3.6. DURAK_ACTIVE_SESSION — активная сессия игрока

Резервирует за человеком одну незавершённую партию. `PLAYER_ID` одновременно
является PK и FK, поэтому у игрока не может быть двух записей.

| Поле | Тип | Ключ | Назначение |
|---|---|---|---|
| `PLAYER_ID` | `NUMBER(19)` | PK, FK | Игрок → `DURAK_PLAYER`. |
| `GAME_ID` | `NUMBER(19)` | FK | Активная партия → `DURAK_GAME`. |
| `OPENED_AT` | `TIMESTAMP WITH TIME ZONE` |  | Время резервирования. |
| `LAST_ACTIVITY_AT` | `TIMESTAMP WITH TIME ZONE` |  | Последний heartbeat. |

### 3.7. DURAK_GAME_CARD — карта партии

Связывает справочную карту с конкретной партией и хранит её текущее положение.
В одной партии создаётся 36 или 52 записи.

| Поле | Тип | Ключ | Назначение |
|---|---|---|---|
| `GAME_ID` | `NUMBER(19)` | PK, FK | Партия → `DURAK_GAME`. |
| `CARD_ID` | `NUMBER(3)` | PK, FK | Карта → `DURAK_CARD`. |
| `DECK_POS` | `NUMBER(3)` | UQ* | Детерминированная позиция в колоде. |
| `CARD_ZONE` | `VARCHAR2(10)` |  | `TALON`, `HAND`, `ATTACK`, `DEFENSE`, `DISCARD`. |
| `OWNER_SEAT_NO` | `NUMBER(1)` | FK* | Владелец руки → `DURAK_GAME_PLAYER`. |
| `TABLE_PAIR_NO` | `NUMBER(2)` |  | Номер пары на столе. |
| `RECEIVED_SEQ` | `NUMBER(19)` |  | Порядок получения карты игроком. |
| `IS_FACE_UP` | `CHAR(1)` |  | Признак открытой карты. |
| `CHANGED_AT` | `TIMESTAMP WITH TIME ZONE` |  | Последнее перемещение. |

`OWNER_SEAT_NO` входит в составной FK `(GAME_ID, OWNER_SEAT_NO)`.

### 3.8. DURAK_ROUND — раунд

Хранит роли и ограничения отдельного цикла атаки/защиты, включая переводы,
пасы и объявление взятия.

| Поле | Тип | Ключ | Назначение |
|---|---|---|---|
| `GAME_ID` | `NUMBER(19)` | PK, FK | Партия → `DURAK_GAME`. |
| `ROUND_NO` | `NUMBER(10)` | PK | Номер раунда. |
| `ROUND_STATUS` | `VARCHAR2(12)` |  | `ACTIVE`, `DEFENDED`, `TAKEN`, `CANCELLED`. |
| `PRIMARY_ATTACKER_SEAT_NO` | `NUMBER(1)` |  | Начальный атакующий. |
| `INITIAL_DEFENDER_SEAT_NO` | `NUMBER(1)` |  | Начальный защитник. |
| `DEFENDER_SEAT_NO` | `NUMBER(1)` |  | Текущий защитник после переводов. |
| `THROW_CURSOR_SEAT_NO` | `NUMBER(1)` |  | Очередь подбрасывания. |
| `NEXT_ATTACKER_SEAT_NO` | `NUMBER(1)` |  | Атакующий следующего раунда. |
| `DEFENDER_HAND_AT_START` | `NUMBER(3)` |  | Размер руки защитника в начале. |
| `ATTACK_LIMIT` | `NUMBER(2)` |  | Допустимое число атак. |
| `CONSECUTIVE_PASSES` | `NUMBER(2)` |  | Счётчик последовательных пасов. |
| `TRANSFER_COUNT` | `NUMBER(2)` |  | Число переводов. |
| `DEFENSE_STARTED` | `CHAR(1)` |  | Была ли положена карта защиты. |
| `TAKE_DECLARED` | `CHAR(1)` |  | Объявлено ли взятие. |
| `OUTCOME_REASON` | `VARCHAR2(100)` |  | Причина результата раунда. |
| `STARTED_AT` | `TIMESTAMP WITH TIME ZONE` |  | Начало раунда. |
| `ENDED_AT` | `TIMESTAMP WITH TIME ZONE` |  | Завершение раунда. |

### 3.9. DURAK_TABLE_PAIR — пара на столе

Представляет один слот игрового стола: обязательную атакующую и необязательную
защитную карту. В раунде допускается до восьми пар.

| Поле | Тип | Ключ | Назначение |
|---|---|---|---|
| `GAME_ID` | `NUMBER(19)` | PK, FK | Часть ссылки на раунд. |
| `ROUND_NO` | `NUMBER(10)` | PK, FK | Раунд → `DURAK_ROUND`. |
| `PAIR_NO` | `NUMBER(2)` | PK | Номер пары. |
| `ATTACK_CARD_ID` | `NUMBER(3)` | FK, UQ* | Атакующая карта → `DURAK_GAME_CARD`. |
| `ATTACKING_SEAT_NO` | `NUMBER(1)` |  | Место подбросившего. |
| `DEFENSE_CARD_ID` | `NUMBER(3)` | FK | Защитная карта → `DURAK_GAME_CARD`. |
| `DEFENDING_SEAT_NO` | `NUMBER(1)` |  | Место защитника. |
| `PAIR_STATUS` | `VARCHAR2(10)` |  | `OPEN`, `COVERED`, `TAKEN`, `DISCARDED`. |
| `ATTACK_EVENT_NO` | `NUMBER(19)` |  | Номер события атаки. |
| `DEFENSE_EVENT_NO` | `NUMBER(19)` |  | Номер события защиты. |
| `CREATED_AT` | `TIMESTAMP WITH TIME ZONE` |  | Создание пары. |
| `COVERED_AT` | `TIMESTAMP WITH TIME ZONE` |  | Время покрытия. |

### 3.10. DURAK_EVENT — событие

Неизменяемый протокол партии. Используется журналом, реплеем, аналитикой и
контролем последовательности изменений.

| Поле | Тип | Ключ | Назначение |
|---|---|---|---|
| `EVENT_ID` | `NUMBER(19)` | PK | Идентификатор события. |
| `GAME_ID` | `NUMBER(19)` | FK, UQ* | Партия → `DURAK_GAME`. |
| `EVENT_NO` | `NUMBER(19)` | UQ* | Последовательный номер внутри партии. |
| `ROUND_NO` | `NUMBER(10)` |  | Номер связанного раунда. |
| `EVENT_TYPE` | `VARCHAR2(30)` |  | Тип игрового или системного события. |
| `EVENT_SOURCE` | `VARCHAR2(10)` |  | `MANUAL`, `SYSTEM`, `TIMEOUT`, `ADMIN`. |
| `ACTOR_PLAYER_ID` | `NUMBER(19)` | FK | Инициатор → `DURAK_PLAYER`. |
| `ACTOR_SEAT_NO` | `NUMBER(1)` |  | Место инициатора. |
| `CARD_ID` | `NUMBER(3)` | FK | Связанная справочная карта. |
| `TARGET_PAIR_NO` | `NUMBER(2)` |  | Целевая пара стола. |
| `TARGET_SEAT_NO` | `NUMBER(1)` |  | Целевой игрок. |
| `PHASE_BEFORE` | `VARCHAR2(20)` |  | Фаза до действия. |
| `PHASE_AFTER` | `VARCHAR2(20)` |  | Фаза после действия. |
| `VERSION_BEFORE` | `NUMBER(19)` |  | Версия партии до действия. |
| `VERSION_AFTER` | `NUMBER(19)` |  | Версия партии после действия. |
| `VISIBILITY_CODE` | `VARCHAR2(10)` |  | `PUBLIC`, `PRIVATE`, `SYSTEM`. |
| `VISIBLE_TO_SEAT_NO` | `NUMBER(1)` |  | Получатель приватного события. |
| `EVENT_MESSAGE` | `VARCHAR2(1000)` |  | Человеко-читаемое описание. |
| `EVENT_PAYLOAD` | `CLOB` |  | JSON с дополнительными данными. |
| `CREATED_AT` | `TIMESTAMP WITH TIME ZONE` |  | Время события. |

### 3.11. DURAK_CARD_MOVE — перемещение карты

Дочерняя запись события. Показывает, откуда и куда переместилась карта, что
позволяет пошагово восстановить партию.

| Поле | Тип | Ключ | Назначение |
|---|---|---|---|
| `CARD_MOVE_ID` | `NUMBER(19)` | PK | Идентификатор перемещения. |
| `GAME_ID` | `NUMBER(19)` | FK* | Часть ссылки на событие и карту партии. |
| `EVENT_ID` | `NUMBER(19)` | FK* | Событие → `DURAK_EVENT`. |
| `CARD_ID` | `NUMBER(3)` | FK* | Карта партии → `DURAK_GAME_CARD`. |
| `FROM_ZONE` | `VARCHAR2(10)` |  | Исходная зона. |
| `TO_ZONE` | `VARCHAR2(10)` |  | Новая зона. |
| `FROM_OWNER_SEAT_NO` | `NUMBER(1)` |  | Прежний владелец. |
| `TO_OWNER_SEAT_NO` | `NUMBER(1)` |  | Новый владелец. |
| `FROM_PAIR_NO` | `NUMBER(2)` |  | Прежняя пара стола. |
| `TO_PAIR_NO` | `NUMBER(2)` |  | Новая пара стола. |
| `IS_FACE_UP_AFTER` | `CHAR(1)` |  | Видимость после перемещения. |
| `CREATED_AT` | `TIMESTAMP WITH TIME ZONE` |  | Время перемещения. |

### 3.12. DURAK_ERROR — журнал отказов

Хранит ошибочные и отклонённые операции в автономной транзакции. Внешние ключи
намеренно не заданы: запись ошибки должна сохраниться даже после отката основной
транзакции или удаления связанной партии.

| Поле | Тип | Ключ | Назначение |
|---|---|---|---|
| `ERROR_ID` | `NUMBER(19)` | PK | Идентификатор ошибки. |
| `GAME_ID` | `NUMBER(19)` | LOGICAL | Идентификатор партии без FK. |
| `PLAYER_ID` | `NUMBER(19)` | LOGICAL | Идентификатор игрока без FK. |
| `DB_USERNAME` | `VARCHAR2(128)` |  | Oracle-пользователь. |
| `ACTION_TYPE` | `VARCHAR2(30)` |  | Отклонённая операция. |
| `ERROR_CODE` | `NUMBER(10)` |  | Код Oracle/приложения. |
| `ERROR_MESSAGE` | `VARCHAR2(1000)` |  | Причина отказа. |
| `ERROR_PAYLOAD` | `CLOB` |  | JSON с параметрами операции. |
| `CREATED_AT` | `TIMESTAMP WITH TIME ZONE` |  | Время регистрации. |

### 3.13. DURAK_DAILY_RESULT — результат Daily

Фиксирует итог каждого участника Daily-партии и показатели для дневного табло.

| Поле | Тип | Ключ | Назначение |
|---|---|---|---|
| `DAILY_RESULT_ID` | `NUMBER(19)` | PK | Идентификатор результата. |
| `DAILY_ID` | `NUMBER(19)` | FK, UQ* | Daily → `DURAK_DAILY`. |
| `GAME_ID` | `NUMBER(19)` | FK, UQ* | Партия → `DURAK_GAME`. |
| `PLAYER_ID` | `NUMBER(19)` | FK, UQ* | Игрок → `DURAK_PLAYER`. |
| `RESULT_CODE` | `VARCHAR2(12)` |  | `WIN`, `LOSS` или `DRAW`. |
| `FINISH_PLACE` | `NUMBER(1)` |  | Место выхода. |
| `ROUNDS_PLAYED` | `NUMBER(10)` |  | Число сыгранных раундов. |
| `ACTIONS_COUNT` | `NUMBER(19)` |  | Число действий. |
| `DURATION_SEC` | `NUMBER(19)` |  | Продолжительность партии. |
| `RECORDED_AT` | `TIMESTAMP WITH TIME ZONE` |  | Время фиксации результата. |

## 4. Связи и кратности

| Родитель | Дочерняя сущность | Кратность | Основание |
|---|---|---|---|
| `DURAK_PLAYER` | `DURAK_GAME` | 1 : 0..N | Один игрок создаёт несколько партий. |
| `DURAK_DAILY` | `DURAK_GAME` | 1 : 0..N | Партия может не относиться к Daily. |
| `DURAK_CARD` | `DURAK_GAME` | 1 : 0..N | Карта может быть козырной во многих партиях. |
| `DURAK_GAME` | `DURAK_GAME_PLAYER` | 1 : 2..6 | В партии участвуют 2–6 игроков. |
| `DURAK_PLAYER` | `DURAK_GAME_PLAYER` | 1 : 0..N | Игрок участвует в разных партиях. |
| `DURAK_PLAYER` | `DURAK_ACTIVE_SESSION` | 1 : 0..1 | Не более одной активной сессии. |
| `DURAK_GAME` | `DURAK_ACTIVE_SESSION` | 1 : 0..N | В активной партии несколько игроков. |
| `DURAK_GAME` | `DURAK_GAME_CARD` | 1 : 36/52 | Экземпляры карт одной партии. |
| `DURAK_CARD` | `DURAK_GAME_CARD` | 1 : 0..N | Одна справочная карта встречается в разных партиях. |
| `DURAK_GAME_PLAYER` | `DURAK_GAME_CARD` | 1 : 0..N | Игрок владеет картами зоны `HAND`; связь необязательна. |
| `DURAK_GAME` | `DURAK_ROUND` | 1 : 0..N | Партия состоит из раундов. |
| `DURAK_ROUND` | `DURAK_TABLE_PAIR` | 1 : 0..8 | Раунд содержит пары атака/защита. |
| `DURAK_GAME_CARD` | `DURAK_TABLE_PAIR` | 1 : 0..N | Две FK-связи: атакующая и защитная карта. |
| `DURAK_GAME` | `DURAK_EVENT` | 1 : 1..N | Протокол событий партии. |
| `DURAK_PLAYER` | `DURAK_EVENT` | 1 : 0..N | Инициатор события может отсутствовать. |
| `DURAK_CARD` | `DURAK_EVENT` | 1 : 0..N | Событие может относиться к карте. |
| `DURAK_EVENT` | `DURAK_CARD_MOVE` | 1 : 0..N | Одно событие перемещает несколько карт. |
| `DURAK_GAME_CARD` | `DURAK_CARD_MOVE` | 1 : 0..N | История перемещений карты партии. |
| `DURAK_DAILY` | `DURAK_DAILY_RESULT` | 1 : 0..N | Результаты одной Daily-конфигурации. |
| `DURAK_GAME` | `DURAK_DAILY_RESULT` | 1 : 0..N | Результаты участников партии. |
| `DURAK_PLAYER` | `DURAK_DAILY_RESULT` | 1 : 0..N | Daily-результаты игрока. |

`DURAK_ERROR.GAME_ID` и `DURAK_ERROR.PLAYER_ID` показаны на диаграмме пунктиром
как логические связи без внешних ключей.

## 5. Обозначения ER-диаграммы

- `PK` — первичный ключ;
- `FK` — внешний ключ;
- `UQ` — уникальное ограничение;
- `LOG` — логическая ссылка без внешнего ключа;
- сплошная линия — физический внешний ключ Oracle;
- пунктирная линия — логическая ссылка журнала ошибок;
- `1`, `0..1`, `0..N`, `2..6`, `36/52` — кратности связей.
