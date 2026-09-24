# Запуск игры в SQL Developer

Проект устанавливается в схему-владельца, например `DURAK_OWNER`. Каждый игрок
подключается своим Oracle-пользователем. Чужие карты скрываются по значению
`SESSION_USER`, поэтому смена `CURRENT_SCHEMA` не раскрывает руки соперников.

## Подготовка владельцем

```sql
@install.sql
@admin/grant_player_access.sql PLAYER_ONE
@admin/grant_player_access.sql PLAYER_TWO
```

Для 3–6 игроков выполните второй сценарий выдачи прав для каждого пользователя.
Прямой доступ к таблицам и пакету `DURAK_ENGINE` игрокам не выдаётся.

## Создание и подключение

Первый игрок:

```sql
@demo/01_creator.sql DURAK_OWNER Михаил demo-seed-1
```

Сценарий выводит `GAME_ID`. Остальные игроки выполняют:

```sql
@demo/02_joiner.sql DURAK_OWNER Анна <GAME_ID>
```

После подключения 2–6 участников создатель запускает игру:

```sql
@demo/03_start.sql DURAK_OWNER <GAME_ID>
```

## Состояние и команды

```sql
SELECT game_text, turn_text, hand_text, table_text,
       players_text, command_hint, last_event_text
FROM v_game_console
WHERE game_id = <GAME_ID>;
```

Переменная результата создаётся один раз:

```sql
VARIABLE message VARCHAR2(1000)
```

Команды:

```sql
EXEC durak_console.play('ХОД 8H', :message)
EXEC durak_console.play('БИТО 9H 1', :message)
EXEC durak_console.play('ПОДКИНУТЬ 8C', :message)
EXEC durak_console.play('ПЕРЕВОД 8D', :message)
EXEC durak_console.play('ВЗЯТЬ', :message)
EXEC durak_console.play('ПАС', :message)
PRINT message
```

Можно передать только код карты, например `8H`: консоль сама выберет атаку,
защиту или подбрасывание по текущей фазе. Справка:

```sql
EXEC durak_console.help(:message)
PRINT message
```

## Создание партии с параметрами

```sql
VARIABLE game_id NUMBER
VARIABLE message VARCHAR2(1000)

BEGIN
  durak_api.create_game(
    p_game_id => :game_id,
    p_message => :message,
    p_deck_size => 52,
    p_game_variant => 'PEREVODNOY',
    p_first_move_mode => 'SEEDED_RANDOM',
    p_turn_timeout_sec => 60,
    p_seed_text => 'demo-seed-52'
  );
END;
/
```

Допустимые значения:

- `p_deck_size`: `36` или `52`;
- `p_game_variant`: `PODKIDNOY` или `PEREVODNOY`;
- `p_first_move_mode`: `LOWEST_TRUMP` или `SEEDED_RANDOM`;
- `p_turn_timeout_sec`: `0` отключает таймер хода.

## Журнал и реплей

Понятный журнал:

```sql
SELECT log_line
FROM v_log_text
WHERE game_id = <GAME_ID>
ORDER BY event_no;
```

Пошаговый реплей:

```sql
SELECT replay_step_no, event_no, event_type, actor_name,
       event_card_code, moved_card_code, from_zone, to_zone,
       phase_before, phase_after, event_message
FROM v_replay
WHERE game_id = <GAME_ID>
ORDER BY replay_step_no;
```

Во время игры реплей скрывает чужие закрытые события. После завершения партии
участникам доступна полная последовательность.

## Daily

```sql
@demo/05_daily.sql DURAK_OWNER Михаил 2026-09-24
```

Остальные игроки подключаются к выведенному `GAME_ID` обычным сценарием
`demo/02_joiner.sql`. После завершения результаты доступны так:

```sql
SELECT *
FROM v_daily_results
WHERE daily_id = <DAILY_ID>
ORDER BY daily_place, finish_place;
```

## Табло

```sql
SELECT display_name, games_played, wins, losses, draws,
       avg_duration_sec, avg_rounds
FROM v_leaderboard
ORDER BY wins DESC, losses, display_name;
```

## Проверка проекта

```sql
@tests/run_all.sql
```

Ожидаемый итог: `успешно 78, ошибок 0`. Проверка одновременного доступа описана
в `tests/concurrency/README.md`.
