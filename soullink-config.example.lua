-- Same configuration contract as Modern Emerald Soul Link.
-- Stage 2 only tests local PING: these settings take effect in the networking stage.
return {
    role = "host", -- "host" for Player 1, "client" for Players 2-4
    host = "127.0.0.1", -- Clients: replace with Player 1's private-network IP
    port = 7777,
    allowSinglePlayer = false, -- Host only: permit an explicitly solo run
}
