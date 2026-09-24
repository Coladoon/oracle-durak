SET VERIFY OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

ACCEPT GAME_ID NUMBER PROMPT 'Введите GAME_ID: '

SELECT game_id, version_no
FROM durak_game
WHERE game_id = &GAME_ID
FOR UPDATE;

PROMPT Партия заблокирована в сессии A.
PAUSE Нажмите Enter только после завершения сценария в сессии B...

ROLLBACK;
PROMPT Блокировка снята.

UNDEFINE GAME_ID
