PROMPT Создание представлений человеко-понятной игровой консоли

CREATE OR REPLACE VIEW v_log_text AS
SELECT
    game_id,
    event_no,
    round_no,
    created_at,
    CASE event_type
        WHEN 'GAME_CREATED' THEN 'Создание игры'
        WHEN 'PLAYER_JOINED' THEN 'Присоединение игрока'
        WHEN 'BOT_ADDED' THEN 'Добавление бота'
        WHEN 'GAME_STARTED' THEN 'Начало игры'
        WHEN 'SHUFFLED' THEN 'Перемешивание колоды'
        WHEN 'DEALT' THEN 'Раздача карты'
        WHEN 'ROUND_STARTED' THEN 'Новый раунд'
        WHEN 'ATTACK' THEN 'Атака'
        WHEN 'THROW_IN' THEN 'Подбрасывание'
        WHEN 'DEFEND' THEN 'Защита'
        WHEN 'TRANSFER' THEN 'Перевод атаки'
        WHEN 'PASS' THEN 'Пас'
        WHEN 'TAKE_DECLARED' THEN 'Решение взять карты'
        WHEN 'TAKE' THEN 'Карты взяты'
        WHEN 'DISCARD' THEN 'Отбой'
        WHEN 'DRAW' THEN 'Добор карты'
        WHEN 'PLAYER_OUT' THEN 'Игрок вышел'
        WHEN 'GAME_FINISHED' THEN 'Конец игры'
        WHEN 'GAME_CANCELLED' THEN 'Отмена игры'
        WHEN 'TIMEOUT' THEN 'Истёк таймер хода'
        WHEN 'IDLE_TIMEOUT' THEN 'Игра завершена из-за простоя'
        WHEN 'BOT_DECISION' THEN 'Решение бота'
        WHEN 'HEARTBEAT' THEN 'Активность игрока'
        ELSE event_type
    END AS action_text,
    actor_name,
    card_code,
    event_message,
    '[' || event_no || '] '
        || CASE WHEN round_no IS NULL THEN '' ELSE 'Раунд ' || round_no || '. ' END
        || CASE event_type
            WHEN 'ATTACK' THEN NVL(actor_name || ': ', '') || 'атакует ' || card_code
            WHEN 'THROW_IN' THEN NVL(actor_name || ': ', '') || 'подкидывает ' || card_code
            WHEN 'DEFEND' THEN NVL(actor_name || ': ', '') || 'бьёт картой ' || card_code
            WHEN 'TRANSFER' THEN NVL(actor_name || ': ', '') || 'переводит картой ' || card_code
            WHEN 'PASS' THEN NVL(actor_name || ': ', '') || 'пасует'
            WHEN 'TAKE_DECLARED' THEN NVL(actor_name || ': ', '') || 'решает взять карты'
            ELSE event_message
        END AS log_line
FROM v_log;

CREATE OR REPLACE VIEW v_game_console AS
WITH my_status AS (
    SELECT status_row.*
    FROM v_game_status status_row
    WHERE status_row.seat_no = status_row.viewer_seat_no
), hand_rows AS (
    SELECT
        game_id,
        LISTAGG(card_code, ' ') WITHIN GROUP (
            ORDER BY is_trump, rank_value, suit_code
        ) AS hand_text
    FROM v_hand_mine
    GROUP BY game_id
), table_rows AS (
    SELECT
        game_id,
        LISTAGG(
            '[' || pair_no || '] ' || attack_card_code
            || CASE
                WHEN defense_card_code IS NULL THEN ' → ?'
                ELSE ' → ' || defense_card_code
            END,
            ' | '
        ) WITHIN GROUP (ORDER BY pair_no) AS table_text
    FROM v_table
    WHERE pair_no IS NOT NULL
    GROUP BY game_id
), player_rows AS (
    SELECT
        game_id,
        LISTAGG(
            display_name || ': ' || hand_count || ' карт (' || player_status || ')',
            ' | '
        ) WITHIN GROUP (ORDER BY seat_no) AS players_text
    FROM v_game_status
    GROUP BY game_id
), last_log AS (
    SELECT game_id, log_line
    FROM (
        SELECT
            game_id,
            log_line,
            ROW_NUMBER() OVER (PARTITION BY game_id ORDER BY event_no DESC) AS row_no
        FROM v_log_text
    )
    WHERE row_no = 1
)
SELECT
    status_row.game_id,
    'Игра #' || status_row.game_id
        || ' | раунд ' || status_row.current_round_no
        || ' | козырь ' || NVL(status_row.trump_card_code, '?')
        || ' | талон ' || status_row.talon_count AS game_text,
    CASE
        WHEN status_row.game_status = 'FINISHED'
            THEN 'Игра окончена. Дурак — ' || NVL(status_row.fool_name, 'не определён') || '.'
        WHEN status_row.current_actor_seat_no = status_row.viewer_seat_no
            THEN 'ВАШ ХОД. Разрешено: ' || status_row.my_allowed_actions || '.'
        ELSE 'Ожидайте: ходит ' || NVL(status_row.current_actor_name, 'система') || '.'
    END AS turn_text,
    NVL(hand_rows.hand_text, 'Рука пуста') AS hand_text,
    NVL(table_rows.table_text, 'Стол пуст') AS table_text,
    player_rows.players_text,
    CASE
        WHEN status_row.my_allowed_actions = 'ATTACK'
            THEN 'Команда: ХОД <карта>, например ХОД 8H'
        WHEN status_row.my_allowed_actions LIKE 'DEFEND%'
            THEN 'Команды: БИТО <карта> [пара] | ВЗЯТЬ'
                || CASE WHEN status_row.my_allowed_actions LIKE '%TRANSFER%'
                    THEN ' | ПЕРЕВОД <карта>' ELSE '' END
        WHEN status_row.my_allowed_actions LIKE '%THROW_IN%'
            THEN 'Команды: ПОДКИНУТЬ <карта> | ПАС'
        WHEN status_row.my_allowed_actions = 'WAIT'
            THEN 'Сейчас ход другого игрока'
        ELSE 'Команды недоступны'
    END AS command_hint,
    last_log.log_line AS last_event_text
FROM my_status status_row
LEFT JOIN hand_rows
  ON hand_rows.game_id = status_row.game_id
LEFT JOIN table_rows
  ON table_rows.game_id = status_row.game_id
LEFT JOIN player_rows
  ON player_rows.game_id = status_row.game_id
LEFT JOIN last_log
  ON last_log.game_id = status_row.game_id;

PROMPT Представления V_GAME_CONSOLE и V_LOG_TEXT созданы
