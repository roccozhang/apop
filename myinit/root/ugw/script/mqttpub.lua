local js = require("cjson.safe")
local mosquitto = require("mosquitto")

local topic, payload = ... 	assert(topic and payload)

mosquitto.init()

local mqtt = mosquitto.new("a/ac/mqttpub", false)
mqtt:login_set("#qmsw2..5#", "@oawifi15%")
local _ = mqtt:connect("127.0.0.1", 61883) or error("connect fail")

mqtt:publish(topic, payload, 0, false)
mqtt:disconnect()
