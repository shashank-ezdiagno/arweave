-module(app_crypto).
-export([start/0, start/1, crypto/5, get_cryptos/3]).
-export([new_transaction/2, message/2]).
-include("ar.hrl").
-include_lib("eunit/include/eunit.hrl").

%%% A de-centralised, uncensorable microblogging platform.
%%% For examplary purposes only.

%% The tag to use for for new cryptos.
-define(CRPTO_TAG, "cryptor").

%% Define the state record for a cryptor node.
-record(state, {
    db = [], % Stores the 'database' of links to cryptos.
    tickers = []
}).

-record(crypto, {
    tx_id,
    text,
    ticker
}).

%% Start a cryptor node.
start() -> start([]).
start(Peers) ->
    adt_simple:start(?MODULE, #state{}, Peers).

%% Check to see if a new transaction contains a crypto,
%% store it if it does.
new_transaction(S, T) ->
    io:fwrite("~w~n",[T#tx.tags]),
    case lists:member(?CRPTO_TAG, T#tx.tags) of
        true ->
            % Transaction contains a crypto! Update the state.
            case lists:member(lists:last(T#tx.tags), S#state.tickers) of
                false ->
                    % Transaction does not contains a crypto! Update the state.
                    S#state { db = add_crypto(S#state.db, T), tickers = lists:append(S#state.tickers, [lists:last(T#tx.tags)]) };
                true ->
                    S#state { db = add_crypto(S#state.db, T), tickers = S#state.tickers}
                    % Transaction isn't for us. Return the state unchanged.
            end;
        false ->
            % Transaction isn't for us. Return the state unchanged.
            S
    end.


%% Handle non-gossip server requests.
message(S, {get_cryptos, ResponsePID, PubKey, Ticker}) ->
    io:format("~p~n", [Ticker]),
    ResponsePID ! {cryptos, PubKey, find_cryptos(S#state.db, PubKey, Ticker)},
    S.

%% Store a crypto in the database.
%% For simplicity, we are currently using a key value list of public keys.
add_crypto(DB, T) ->
    NewChirp = #crypto { tx_id = T#tx.id, text = bitstring_to_list(T#tx.data), ticker = lists:last(T#tx.tags)},
    case lists:keyfind(T#tx.owner, 1, DB) of
        false -> [{T#tx.owner, [NewChirp]}|DB];
        {PubKey, Chirps} ->
            lists:keyreplace(PubKey, 1, DB, {PubKey, [NewChirp|Chirps]})
    end.

%% Find cryptos associated with a public key and return them.
find_cryptos(DB, PubKey, Ticker) ->
    case lists:keyfind(PubKey, 1, DB) of
        {PubKey, Chirps} ->
            io:format("~p~n", [Chirps]),
            io:format("~p~n", [lists:keyfind(Ticker, #crypto.ticker, Chirps)]),
            % case lists:keyfind(Ticker, #crypto.ticker, Chirps) of
            %     {ChirpsMin} -> ChirpsMin;
            %     false -> []
            % end;
            Gt10 = fun(X) -> X#crypto.ticker == Ticker end,
            lists:filter(Gt10, Chirps);
        false -> []
    end.

%% Submit a new crypto to the system. Needs a peer to send the new transaction
%% to, as well as the private and public key of the wallet sending the tx.
%% NOTE: In a 'real' system, the transaction would be prepared by the server
%% then sent to the user's web browser extension for signing (after the user
%% agrees), limiting private key's exposure. Even here the private key is not
%% exposed to the application server.
crypto(Pub, Priv, Ticker, Text, Peer) ->
    % Generate the transaction.
    TX = ar_tx:new(list_to_bitstring(Text)),
    % Add the cryptor tg to the TX
    PreparedTX = TX#tx { tags = [?CRPTO_TAG, Ticker] },
    % Sign the TX with the public and private key.
    SignedTX = ar_tx:sign(PreparedTX, Priv, Pub),
    ar_node:add_tx(Peer, SignedTX).

%% Get the cryptos that a server knows.
get_cryptos(Server, PubKey, Ticker) ->
    Server ! {get_cryptos, self(), PubKey, Ticker},
    receive
        {cryptos, PubKey, Chirps} -> Chirps
    end.

%% Test that a crypto submitted to the network is found and can be retreived.
basic_usage_test() ->
    % Spawn a network with two nodes and a cryptor server
    ChirpServer = start(),
    Peers = ar_network:start(100, 10),
    ar_node:add_peers(hd(Peers), ChirpServer),
    % Create the transaction, send it.
    {Priv, Pub} = ar_wallet:new(),
    crypto(Pub, Priv, "GOOG", "Hello world!", hd(Peers)),
    crypto(Pub, Priv, "GOOB", "Hello GOOG!", hd(Peers)),
    receive after 250 -> ok end,
    ar_node:mine(hd(Peers)),
    receive after 500 -> ok end,
    [Chirp1] = get_cryptos(ChirpServer, Pub, "GOOG"),
    io:format("~p", [Chirp1#crypto.ticker]),
    "GOOG" = Chirp1#crypto.ticker.
