# Запуск партии из двух терминалов

Проект устанавливается в отдельную схему-владельца, например `DURAK_OWNER`.
Каждый человек подключается своим Oracle-пользователем. Представления используют
`SESSION_USER`, поэтому смена `CURRENT_SCHEMA` не раскрывает чужие руки.

## Подготовка владельцем проекта

```sql
@install.sql
@admin/grant_player_access.sql PLAYER_ONE
@admin/grant_player_access.sql PLAYER_TWO
```

Прямые права на таблицы и пакет `DURAK_ENGINE` игрокам выдавать нельзя.

## Терминал первого игрока

```sql
@demo/01_creator.sql DURAK_OWNER Михаил demo-seed-1
```

Сценарий напечатает `GAME_ID`. Его нужно передать второму игроку.

## Терминал второго игрока

```sql
@demo/02_joiner.sql DURAK_OWNER Анна <GAME_ID>
```

## Старт и действия

Создатель запускает игру:

```sql
@demo/03_start.sql DURAK_OWNER <GAME_ID>
```

Оба игрока используют `demo/04_actions.sql` как шаблон. Перед действием следует
прочитать `V_GAME_STATUS`, `V_TABLE` и `V_HAND_MINE`: они показывают текущую роль,
разрешённые команды и только собственные карты.

Каждая операция `DURAK_API` атомарна и сама завершает транзакцию. Успех и отказ
печатаются через `DBMS_OUTPUT`; последние отказы также доступны в `V_ERRORS`.

## Daily-партия против бота

Одним сценарием можно зарегистрироваться, создать раскладку дня, добавить бота и
запустить игру:

```sql
@demo/05_daily_bot.sql DURAK_OWNER Михаил HARD
```

Уровни сложности: `EASY`, `NORMAL`, `HARD`. После каждого действия человека API
автоматически выполняет действия ботов, пока ход снова не перейдёт человеку.

Тот же сценарий вручную:

```sql
VARIABLE game_id NUMBER
VARIABLE daily_id NUMBER
VARIABLE bot_id NUMBER
VARIABLE bot_seat NUMBER
VARIABLE message VARCHAR2(1000)

BEGIN
  durak_api.create_daily_game(
    p_game_id => :game_id,
    p_daily_id => :daily_id,
    p_message => :message
  );
  durak_api.add_bot(
    p_game_id => :game_id,
    p_bot_player_id => :bot_id,
    p_seat_no => :bot_seat,
    p_message => :message,
    p_bot_level => 'NORMAL'
  );
  durak_api.start_game(:game_id, :message);
END;
/
```

## Реплей и аналитика

Во время активной партии `V_REPLAY` соблюдает те же ограничения видимости, что и
`V_LOG`. После завершения участникам доступен полный порядок событий и перемещений
карт:

```sql
SELECT *
FROM v_replay
WHERE game_id = :game_id
ORDER BY replay_step_no;

SELECT *
FROM v_analytics
WHERE game_id = :game_id;

SELECT *
FROM v_daily_results
WHERE daily_id = :daily_id
ORDER BY daily_place;
```

## Турнир

Создатель может открыть круговой турнир либо олимпийскую сетку, добавить людей
и ботов, а затем сформировать расписание:

```sql
VARIABLE tournament_id NUMBER
VARIABLE bot_id NUMBER
VARIABLE message VARCHAR2(1000)

BEGIN
  durak_api.create_tournament(
    p_tournament_id => :tournament_id,
    p_message => :message,
    p_tournament_name => 'Учебный турнир',
    p_tournament_format => 'ROUND_ROBIN',
    p_seed_text => 'tournament-demo-seed'
  );
  durak_api.add_tournament_bot(
    p_tournament_id => :tournament_id,
    p_bot_player_id => :bot_id,
    p_message => :message,
    p_bot_level => 'NORMAL'
  );
  durak_api.start_tournament(:tournament_id, :message);
END;
/
```

Другой зарегистрированный Oracle-пользователь присоединяется до старта вызовом
`DURAK_API.JOIN_TOURNAMENT`. Запланированный матч запускается по его
`TOURNAMENT_MATCH_ID`:

```sql
VARIABLE game_id NUMBER

BEGIN
  durak_api.start_tournament_match(
    p_tournament_match_id => <TOURNAMENT_MATCH_ID>,
    p_game_id => :game_id,
    p_message => :message
  );
END;
/

SELECT *
FROM v_tournament
WHERE tournament_id = :tournament_id
ORDER BY tournament_round_no, match_no;

SELECT *
FROM v_tournament_standings
WHERE tournament_id = :tournament_id
ORDER BY standing_place, seed_no;
```

В олимпийской сетке ничья разрешается детерминированно: дальше проходит участник
с меньшим `SEED_NO`, а сам результат партии остаётся ничьей в статистике.

## Проверка двух одновременных сессий

Пошаговый сценарий блокировки одной партии двумя терминалами находится в
`tests/concurrency/README.md`.
