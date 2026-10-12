-- Same configuration contract as Modern Emerald Soul Link.
-- BizHawk must also be launched with matching --socket-ip / --socket-port arguments.
-- Stage 4: everyone uses this script/config pair; Player 1 also runs the relay.
return {
    role = "host", -- "host" for Player 1, "client" for Players 2-4
    host = "127.0.0.1", -- Clients: replace with Player 1's private-network IP
    port = 7777,
    allowSinglePlayer = false, -- Host only: permit an explicitly solo run
}
