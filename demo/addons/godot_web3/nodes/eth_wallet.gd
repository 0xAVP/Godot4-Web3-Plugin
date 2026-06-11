@icon("res://addons/godot_web3/icons/icon.svg") 
class_name EthWallet extends Node

signal unlocked
signal locked

# --- Конфигурация ---
enum WalletType { BRAIN_WALLET, SIMPLE_RANDOM }

## Тип реализации кошелька.
## [br][b]BRAIN_WALLET[/b]: Генерирует ключ на основе пароля и соли (детерминированно).
## [br][b]SIMPLE_RANDOM[/b]: Создает случайный одноразовый кошелек в памяти при старте. Пароль для разблокировки не требуется.
@export var type: WalletType = WalletType.BRAIN_WALLET

@export_group("Brain Wallet Settings")

## Уникальный идентификатор вашего приложения (App ID / Secret).
## [br][color=yellow]ВНИМАНИЕ:[/color] Используйте длинную случайную строку. 
## Это защищает базу паролей ваших игроков от массового брутфорса.
## Если вы измените это значение после релиза, игроки потеряют доступ к своим старым кошелькам.
@export var app_id: String = "PLEASE_REPLACE_WITH_A_LONG_UNIQUE_SECRET_STRING"

## Количество итераций хеширования (Time Cost).
## Влияет на время генерации ключа и сложность подбора пароля.
## [br]Рекомендуемые значения: 1-4 для игр (чтобы не фризить интерфейс надолго), 10+ для высокой безопасности.
@export_range(1, 10) var iterations: int = 2

## Объем памяти в Килобайтах, используемый алгоритмом Argon2id (Memory Cost).
## [br]65536 КБ = 64 МБ.
## [br]Чем выше значение, тем сложнее злоумышленнику использовать GPU/ASIC для брутфорса паролей.
@export var memory_kb: int = 65536

## Степень параллелизма (количество потоков), используемое при генерации.
@export_range(1, 4) var parallelism: int = 1

@export_group("Simple Wallet Settings")

## Приватный ключ в формате Hex (например: 0x123... или 123...).
## Если поле пустое, при старте будет сгенерирован случайный ключ.
## [br][color=yellow]ВНИМАНИЕ:[/color] Не храните здесь ключи с реальными средствами!
@export var simple_private_key: String = ""

# --- Внутренности ---
var _impl: RefCounted = null # Сюда положим EthBrainWallet

func _ready():
	_setup_implementation()

func _setup_implementation():
	match type:
		WalletType.BRAIN_WALLET:
			# Подгружаем скрипт реализации динамически, как в EthClient
			var BrainImpl = load("res://addons/godot_web3/nodes/internal/wallet/eth_brain_wallet.gd")
			_impl = BrainImpl.new({
				"salt": app_id,
				"iterations": iterations,
				"memory": memory_kb,
				"parallelism": parallelism
			})
		WalletType.SIMPLE_RANDOM:
			var ScriptCls = load("res://addons/godot_web3/nodes/internal/wallet/eth_simple_wallet.gd")
			
			# --- ИЗМЕНЕНИЕ ЗДЕСЬ ---
			# Собираем конфиг. Если ключ задан в инспекторе, передаем его.
			var config = {}
			if not simple_private_key.is_empty():
				config["private_key_hex"] = simple_private_key
			
			# Создаем реализацию (если config пустой, она сама сгенерирует рандом)
			_impl = ScriptCls.new(config)
			# -----------------------
			
			# Random кошелек готов к работе сразу (или если ключ валидный)
			# Эмитим сигнал отложенно, чтобы другие ноды успели подписаться в _ready
			call_deferred("emit_signal", "unlocked")

# --- Public API (Фасад) ---

func unlock(password: String, extra_entropy: Array = []) -> bool:
	if not _impl: return false
	var success = _impl.unlock(password, extra_entropy)
	if success: unlocked.emit()
	return success

func lock() -> void:
	if _impl:
		_impl.lock()
	emit_signal("locked")

func is_unlocked() -> bool:
	return _impl.is_unlocked() if _impl else false

func get_address() -> String:
	return _impl.get_address() if _impl else ""

func sign_transaction(tx: W3Transaction) -> String:
	if not is_unlocked():
		push_error("EthWallet: Wallet is locked")
		return ""
	return _impl.sign_transaction(tx)

func sign_message(message: String) -> String:
	if not is_unlocked(): return ""
	return _impl.sign_message(message)

func get_private_key_qr(scale: int = 10) -> ImageTexture:
	if not is_unlocked(): return null
	return _impl.get_private_key_qr(scale)

func verify_credentials(password: String, extra_entropy: Array = []) -> bool:
	if not _impl: return false
	return _impl.verify_credentials(password, extra_entropy)

func sign_raw_hash(hash: PackedByteArray) -> String:
	if not is_unlocked(): return ""
	return _impl.sign_raw_hash(hash)

func _exit_tree():
	# Когда нода кошелька удаляется (закрытие игры/смена сцены),
	# мы принудительно затираем ключи в реализации, пока она еще жива.
	if _impl:
		_impl.lock()
