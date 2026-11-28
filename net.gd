extends Node
## Ağ katmanı: Steam lobi (Herkese Açık / Arkadaşlar / Oda Kodu) + SteamMultiplayerPeer (Valve relay),
## tek PC / yerel ağ testi için ENet yedeği ve Host oyuncu atma (kick).

signal status(msg: String)
signal lobby_changed
signal left
signal invited(from_name: String, lobby: int)
signal lobby_list_updated(lobbies: Array)

const APP_ID := 480 # Spacewar test App ID'si; kendi Steam App ID'n alınınca bunu değiştir.
const LOCAL_PORT := 7777
const MAX_PLAYERS := 8
const GAME_TAG := "bazar_market_v1"
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

var steam_ok := false
var lobby_id := 0
var lobby_code := ""
var lobby_name := ""
var lobby_is_public := true
var names := {} # peer_id -> görünen ad
var ready_peers := {} # dünyasını kurmuş istemciler (host yönetir, herkese senkron)
var _pending_code := ""
var _pending_lobby_name := ""


func _ready() -> void:
	var r: Dictionary = Steam.steamInitEx(APP_ID, true)
	steam_ok = r.get("status", 1) == 0
	if steam_ok:
		Steam.lobby_created.connect(_on_lobby_created)
		Steam.lobby_joined.connect(_on_lobby_joined)
		Steam.join_requested.connect(_on_join_requested)
		Steam.lobby_invite.connect(func(inviter, lobby, _game): invited.emit(Steam.getFriendPersonaName(inviter), lobby))
		Steam.lobby_chat_update.connect(func(_a, _b, _c, _d): lobby_changed.emit())
		if Steam.has_signal("lobby_match_list"):
			Steam.lobby_match_list.connect(_on_lobby_match_list)
	else:
		push_warning("Steam başlatılamadı: %s" % r)
	multiplayer.peer_connected.connect(func(_id): lobby_changed.emit())
	multiplayer.peer_disconnected.connect(_on_peer_left)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): status.emit(L10n.pick("Bağlantı başarısız.", "Connection failed.")); leave())
	multiplayer.server_disconnected.connect(func(): status.emit(L10n.pick("Host ayrıldı.", "Host disconnected.")); leave())


func my_name() -> String:
	return Steam.getPersonaName() if steam_ok else L10n.pick("Oyuncu", "Player")


func display_name(id: int) -> String:
	return names.get(id, "%s %d" % [L10n.pick("Oyuncu", "Player"), id])


func online() -> bool:
	var p := multiplayer.multiplayer_peer
	return p != null and not (p is OfflineMultiplayerPeer) \
		and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## RPC içinde: gönderen host mu (ya da çevrimdışı / yerel çağrı)?
func from_host() -> bool:
	return not online() or multiplayer.get_remote_sender_id() in [0, 1]


static func _gen_room_code() -> String:
	var out := ""
	for _i in 4:
		out += CODE_CHARS[randi() % CODE_CHARS.length()]
	return out


# --- Steam Lobileri ---

func host_steam(is_public := true, custom_name := "") -> void:
	if not steam_ok:
		status.emit(L10n.pick("Steam açık değil / başlatılamadı.", "Steam is not running."))
		return
	leave()
	lobby_is_public = is_public
	_pending_lobby_name = custom_name.strip_edges().left(36)
	var ltype := Steam.LOBBY_TYPE_PUBLIC if is_public else Steam.LOBBY_TYPE_FRIENDS_ONLY
	Steam.createLobby(ltype, MAX_PLAYERS)
	status.emit(L10n.pick("Lobi kuruluyor...", "Creating lobby..."))


func request_public_lobbies() -> void:
	if not steam_ok:
		lobby_list_updated.emit([])
		status.emit(L10n.pick("Steam bağlı değil.", "Steam is offline."))
		return
	_pending_code = ""
	if Steam.has_method("addRequestLobbyListStringFilter"):
		Steam.addRequestLobbyListStringFilter("game", GAME_TAG, Steam.LOBBY_COMPARISON_EQUAL)
	if Steam.has_method("addRequestLobbyListDistanceFilter"):
		Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	if Steam.has_method("addRequestLobbyListResultCountFilter"):
		Steam.addRequestLobbyListResultCountFilter(30)
	Steam.requestLobbyList()
	status.emit(L10n.pick("Açık pazarlar aranıyor...", "Searching open bazaars..."))


func join_by_code(code: String) -> void:
	var norm := code.strip_edges().to_upper()
	if norm.length() < 4:
		status.emit(L10n.pick("Geçerli bir 4 haneli oda kodu gir.", "Enter a valid 4-character room code."))
		return
	if not steam_ok:
		status.emit(L10n.pick("Oda kodu için Steam açık olmalı.", "Steam must be open to join by code."))
		return
	_pending_code = norm
	if Steam.has_method("addRequestLobbyListStringFilter"):
		Steam.addRequestLobbyListStringFilter("game", GAME_TAG, Steam.LOBBY_COMPARISON_EQUAL)
		Steam.addRequestLobbyListStringFilter("code", norm, Steam.LOBBY_COMPARISON_EQUAL)
	if Steam.has_method("addRequestLobbyListDistanceFilter"):
		Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.requestLobbyList()
	status.emit(L10n.pick("Oda kodu aranıyor: %s...", "Searching room code: %s...") % norm)


func _on_lobby_match_list(lobbies: Array) -> void:
	if _pending_code != "":
		var want := _pending_code
		_pending_code = ""
		if lobbies.is_empty():
			status.emit(L10n.pick("'%s' kodlu oda bulunamadı.", "Room '%s' not found.") % want)
			return
		join_lobby(int(lobbies[0]))
		return
	var out := []
	for lid in lobbies:
		var id := int(lid)
		var lname := str(Steam.getLobbyData(id, "name"))
		var code := str(Steam.getLobbyData(id, "code"))
		var ver := str(Steam.getLobbyData(id, "ver"))
		var cnt := int(Steam.getNumLobbyMembers(id))
		var mx := int(Steam.getLobbyMemberLimit(id))
		if cnt <= 0 or cnt >= mx:
			continue
		out.append({
			"id": id,
			"name": lname if lname != "" else L10n.pick("Semt Pazarı", "Street Bazaar"),
			"code": code,
			"ver": ver,
			"players": cnt,
			"max": mx if mx > 0 else MAX_PLAYERS,
		})
	lobby_list_updated.emit(out)
	status.emit(L10n.pick("%d açık pazar bulundu.", "Found %d open bazaar(s).") % out.size())


## Çevrimiçi Steam arkadaşları: [[steam_id, ad, lobi_id (yoksa 0)], ...]
func online_friends() -> Array:
	var out := []
	if not steam_ok:
		return out
	for i in Steam.getFriendCount(Steam.FRIEND_FLAG_IMMEDIATE):
		var id: int = Steam.getFriendByIndex(i, Steam.FRIEND_FLAG_IMMEDIATE)
		if Steam.getFriendPersonaState(id) != Steam.PERSONA_STATE_OFFLINE:
			var g: Dictionary = Steam.getFriendGamePlayed(id)
			var lobby: int = g.get("lobby", 0) if g.get("id", 0) == APP_ID else 0
			out.append([id, Steam.getFriendPersonaName(id), lobby])
	return out


func join_lobby(id: int) -> void:
	_on_join_requested(id, 0)


func invite_friend(id: int, friend_name: String) -> void:
	if lobby_id == 0:
		status.emit(L10n.pick("Önce Steam lobisi kur.", "Create a Steam lobby first."))
		return
	if Steam.inviteUserToLobby(lobby_id, id):
		status.emit(L10n.pick("%s davet edildi. Steam sohbetinden katılabilir.", "Invited %s via Steam chat.") % friend_name)
	else:
		status.emit(L10n.pick("Davet gönderilemedi.", "Failed to send invite."))


func _new_steam_peer() -> SteamMultiplayerPeer:
	var peer := SteamMultiplayerPeer.new()
	peer.set_server_relay(true)
	peer.set_no_nagle(true)
	return peer


func _on_lobby_created(result: int, id: int) -> void:
	if result != 1:
		status.emit(L10n.pick("Lobi kurulamadı (kod %d).", "Failed to create lobby (code %d).") % result)
		return
	lobby_id = id
	lobby_code = _gen_room_code()
	lobby_name = _pending_lobby_name if _pending_lobby_name != "" else (my_name() + L10n.pick(" Pazarı", "'s Bazaar"))
	Steam.setLobbyData(id, "game", GAME_TAG)
	Steam.setLobbyData(id, "ver", Updater.version())
	Steam.setLobbyData(id, "name", lobby_name)
	Steam.setLobbyData(id, "code", lobby_code)
	Steam.setLobbyData(id, "public", "1" if lobby_is_public else "0")
	var peer := _new_steam_peer()
	peer.host_with_lobby(id)
	multiplayer.multiplayer_peer = peer
	_register_self()
	status.emit(L10n.pick("Lobi hazır! Oda kodu: %s", "Lobby ready! Room code: %s") % lobby_code)
	SteamMgr.set_presence_lobby(1, MAX_PLAYERS)


func _on_join_requested(id: int, _friend: int) -> void:
	leave()
	Steam.joinLobby(id)
	status.emit(L10n.pick("Lobiye katılınıyor...", "Joining lobby..."))


func _on_lobby_joined(id: int, _perm: int, _locked: bool, response: int) -> void:
	if response != 1:
		status.emit(L10n.pick("Lobiye katılınamadı (kod %d).", "Could not join lobby (code %d).") % response)
		return
	if Steam.getLobbyOwner(id) == Steam.getSteamID():
		return
	lobby_id = id
	lobby_code = str(Steam.getLobbyData(id, "code"))
	lobby_name = str(Steam.getLobbyData(id, "name"))
	var peer := _new_steam_peer()
	peer.connect_to_lobby(id)
	multiplayer.multiplayer_peer = peer
	status.emit(L10n.pick("Hosta bağlanılıyor...", "Connecting to host..."))


# --- Tek PC / LAN testi (ENet) ---

func local_port() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("port=") and a.substr(5).is_valid_int():
			return clampi(a.substr(5).to_int(), 1024, 65535)
	return LOCAL_PORT


func host_local() -> void:
	leave()
	var p := ENetMultiplayerPeer.new()
	if p.create_server(local_port(), MAX_PLAYERS) != OK:
		status.emit(L10n.pick("Port %d açılamadı.", "Could not open port %d.") % local_port())
		return
	multiplayer.multiplayer_peer = p
	lobby_code = "LAN"
	_register_self()
	status.emit(L10n.pick("Yerel host açık (port %d).", "Local host open (port %d).") % local_port())


func join_local(ip := "127.0.0.1") -> void:
	leave()
	var target := ip.strip_edges()
	if target == "":
		target = "127.0.0.1"
	var p := ENetMultiplayerPeer.new()
	if p.create_client(target, local_port()) != OK:
		status.emit(L10n.pick("İstemci oluşturulamadı.", "Could not create client."))
		return
	multiplayer.multiplayer_peer = p
	status.emit(L10n.pick("Yerel hosta bağlanılıyor (%s)...", "Connecting to local host (%s)...") % target)


# --- Host Kick ---

func kick_peer(peer_id: int) -> void:
	if not online() or not multiplayer.is_server() or peer_id <= 1:
		return
	rpc_kicked.rpc_id(peer_id)
	if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.has_method("disconnect_peer"):
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


@rpc("authority", "reliable")
func rpc_kicked() -> void:
	status.emit(L10n.pick("Host tarafından odadan çıkarıldın.", "You were kicked by the host."))
	leave()


# --- Ortak ---

func leave() -> void:
	if steam_ok and lobby_id != 0:
		Steam.leaveLobby(lobby_id)
	lobby_id = 0
	lobby_code = ""
	lobby_name = ""
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	names.clear()
	ready_peers.clear()
	Settings.muted_peers.clear()
	SteamMgr.set_presence_menu()
	left.emit()


func _on_peer_left(id: int) -> void:
	names.erase(id)
	ready_peers.erase(id)
	Settings.muted_peers.erase(id)
	if multiplayer.is_server():
		sync_names.rpc(names)
		sync_ready.rpc(ready_peers)
	lobby_changed.emit()


func _on_connected() -> void:
	_register_self()
	status.emit(L10n.pick("Bağlandı. Hostun pazarı açmasını bekle.", "Connected. Waiting for host to open the bazaar."))


func _register_self() -> void:
	var n := my_name()
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		n += " #%d" % (multiplayer.get_unique_id() % 1000)
	if multiplayer.is_server():
		names[1] = n
		lobby_changed.emit()
	else:
		register_name.rpc_id(1, n)


@rpc("any_peer", "reliable")
func register_name(n: String) -> void:
	if not multiplayer.is_server():
		return
	names[multiplayer.get_remote_sender_id()] = n.left(32)
	sync_names.rpc(names)
	lobby_changed.emit()


@rpc("authority", "reliable")
func sync_names(d: Dictionary) -> void:
	names = d
	if lobby_id != 0:
		SteamMgr.set_presence_lobby(names.size(), MAX_PLAYERS)
	lobby_changed.emit()


# --- Hazır eşler (katılım yarışı) ---

## İstemci: start_game/snapshot uygulandı, senk paketleri alabilirim.
@rpc("any_peer", "reliable")
func rpc_peer_ready() -> void:
	if not multiplayer.is_server():
		return
	ready_peers[multiplayer.get_remote_sender_id()] = true
	sync_ready.rpc(ready_peers)


@rpc("authority", "reliable")
func sync_ready(d: Dictionary) -> void:
	ready_peers = d


## Unreliable senk RPC'sini yalnızca dünyasını kurmuş eşlere (host her zaman) gönderir.
func rpc_ready(c: Callable, args: Array) -> void:
	var me := multiplayer.get_unique_id()
	for id in multiplayer.get_peers():
		if id != me and (id == 1 or ready_peers.has(id)):
			c.bindv(args).rpc_id(id)
