id = 0
wrk.method = "GET"
request = function()
    wrk.path = "/v0/entity?id=" .. math.random(0, 1000000)
    id = id + 1
    return wrk.format(nil)
end