@icon("res://addons/godot_web3/icons/icon.svg")
class_name EthRelayer extends Node

## Сигналы для отслеживания статуса
signal relay_started(job_id: String)
signal relay_success(tx_hash: String)
signal relay_failed(error_msg: String)

@export_group("Relayer API")
## URL вашего Fastify сервера (например, http://localhost:3000/relay)
@export var relayer_url: String = ""

@export_group("Forwarder Contract")
## Адрес контракта HexForwarder в сети
@export var forwarder_address: String = ""
## Имя форвардера для домена EIP-712 (как в конструкторе Solidity)
@export var forwarder_name: String = "HexForwarder"
## Версия форвардера (обычно "1")
@export var forwarder_version: String = "1"

@export_group("Settings")
## Время жизни подписи в секундах
@export var deadline_offset: int = 3600 

var _http: HTTPRequest

func _ready():
	# Создаем HTTPRequest динамически, чтобы не загромождать дерево сцены вручную
	_http = HTTPRequest.new()
	add_child(_http)

## Собирает данные для EIP-712 и возвращает хеш для подписи
func get_request_hash(client: EthClient, from_addr: String, to_addr: String, data: PackedByteArray, nonce: int, gas: int, value: W3BigInt = null) -> PackedByteArray:
	var domain = {
		"name": forwarder_name,
		"version": forwarder_version,
		"chainId": client.chain_id,
		"verifyingContract": forwarder_address
	}
	
	var message = {
		"from": from_addr,
		"to": to_addr,
		"value": value if value else W3BigInt.from_int(0),
		"gas": gas,
		"nonce": nonce,
		"deadline": int(Time.get_unix_time_from_system()) + deadline_offset,
		"data": data
	}
	
	# Вызываем наш новый C++ метод
	return W3Crypto.get_eip712_forward_request_hash(domain, message)

## Отправляет подписанный запрос на сервер релейера
func send_relay_transaction(request_data: Dictionary, signature: String) -> String:
	if relayer_url.is_empty():
		push_error("EthRelayer: Relayer URL is not set")
		return ""

	var payload = {
		"request": request_data,
		"signature": signature
	}
	
	var json_payload = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	
	_http.request(relayer_url, headers, HTTPClient.METHOD_POST, json_payload)
	
	# Ждем ответа от сервера
	var res = await _http.request_completed
	var response_code = res[1]
	var body = res[3].get_string_from_utf8()
	
	var json = JSON.parse_string(body)
	
	if response_code == 200 or response_code == 201:
		if json and json.has("jobId"):
			relay_started.emit(str(json["jobId"]))
			# Если релейер сразу вернул хеш (в зависимости от настроек API)
			if json.has("hash"): 
				relay_success.emit(json["hash"])
				return json["hash"]
			return "queued_" + str(json["jobId"])
	else:
		var err_msg = "Unknown error"
		if json and json.has("error"): err_msg = json["error"]
		relay_failed.emit(err_msg)
		push_error("EthRelayer Error (%d): %s" % [response_code, err_msg])
		
	return ""

## Вспомогательный метод для сборки словаря ForwardRequest (нужен для отправки в JSON)
func build_request_dict(from_addr: String, to_addr: String, data: PackedByteArray, nonce: int, gas: int, value: W3BigInt = null) -> Dictionary:
	return {
		"from": from_addr,
		"to": to_addr,
		"value": value.to_string_val() if value else "0",
		"gas": gas,
		"nonce": nonce,
		"deadline": int(Time.get_unix_time_from_system()) + deadline_offset,
		"data": W3Utils.bytes_to_hex(data)
	}
