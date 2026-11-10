-- The node's unit conversions (D238): a typed line such as "5km in mi" read into a value and two units, the
-- conversion between them, and the short text the answer is shown with. Pure: only math, no I/O.

local M = {}

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Every unit is filed under the names it can be typed as, all lower-case; the one exception is a bare b
-- (bit) against a bare B (byte), which the lookup below handles before it lower-cases anything.
local UNITS = {}

local function add(kind, factor, short, names)
    for _, name in ipairs(names) do
        UNITS[name] = { kind = kind, factor = factor, short = short }
    end
end

-- length, base metre
add("length", 0.001, "mm", { "mm", "millimetre", "millimetres", "millimeter", "millimeters" })
add("length", 0.01, "cm", { "cm", "centimetre", "centimetres", "centimeter", "centimeters" })
add("length", 1, "m", { "m", "metre", "metres", "meter", "meters" })
add("length", 1000, "km", { "km", "kilometre", "kilometres", "kilometer", "kilometers" })
add("length", 0.0254, "in", { "in", "inch", "inches" })
add("length", 0.3048, "ft", { "ft", "foot", "feet" })
add("length", 0.9144, "yd", { "yd", "yard", "yards" })
add("length", 1609.344, "mi", { "mi", "mile", "miles" })
add("length", 1852, "nmi", { "nmi" })

-- mass, base kilogram
add("mass", 0.000001, "mg", { "mg", "milligram", "milligrams" })
add("mass", 0.001, "g", { "g", "gram", "grams" })
add("mass", 1, "kg", { "kg", "kilo", "kilos", "kilogram", "kilograms" })
add("mass", 1000, "t", { "t", "tonne", "tonnes", "ton", "tons" })
add("mass", 0.028349523125, "oz", { "oz", "ounce", "ounces" })
add("mass", 0.45359237, "lb", { "lb", "lbs", "pound", "pounds" })
add("mass", 6.35029318, "st", { "st", "stone", "stones" })

-- time, base second
add("time", 0.001, "ms", { "ms", "millisecond", "milliseconds" })
add("time", 1, "s", { "s", "sec", "secs", "second", "seconds" })
add("time", 60, "min", { "min", "mins", "minute", "minutes" })
add("time", 3600, "h", { "h", "hr", "hrs", "hour", "hours" })
add("time", 86400, "day", { "day", "days" })
add("time", 604800, "week", { "week", "weeks" })
add("time", 31536000, "year", { "year", "years" })

-- temperature, base kelvin; the factors are unused because the scales are affine
add("temperature", 1, "c", { "c", "celsius", "°c" })
add("temperature", 1, "f", { "f", "fahrenheit", "°f" })
add("temperature", 1, "k", { "k", "kelvin" })

-- volume, base litre
add("volume", 0.001, "ml", { "ml", "millilitre", "millilitres", "milliliter", "milliliters" })
add("volume", 1, "l", { "l", "litre", "litres", "liter", "liters" })
add("volume", 3.785411784, "gal", { "gal", "gallon", "gallons" })
add("volume", 0.946352946, "qt", { "qt", "quart", "quarts" })
add("volume", 0.473176473, "pt", { "pt", "pint", "pints" })
add("volume", 0.2365882365, "cup", { "cup", "cups" })
add("volume", 0.0295735295625, "floz", { "floz" })
add("volume", 0.01478676478125, "tbsp", { "tbsp", "tablespoon", "tablespoons" })
add("volume", 0.00492892159375, "tsp", { "tsp", "teaspoon", "teaspoons" })
add("volume", 1000, "m3", { "m3" })

-- area, base square metre
add("area", 0.0001, "cm2", { "cm2" })
add("area", 1, "m2", { "m2" })
add("area", 1000000, "km2", { "km2" })
add("area", 10000, "ha", { "ha", "hectare", "hectares" })
add("area", 4046.8564224, "acre", { "acre", "acres" })
add("area", 0.09290304, "ft2", { "ft2" })
add("area", 2589988.110336, "mi2", { "mi2" })

-- speed, base metre per second
add("speed", 1, "m/s", { "m/s" })
add("speed", 1000 / 3600, "km/h", { "km/h", "kmh", "kph" })
add("speed", 0.44704, "mph", { "mph" })
add("speed", 1852 / 3600, "knot", { "knot", "knots", "kt" })

-- data, base byte; b is a bit and B a byte, the only place case matters
add("data", 0.125, "b", { "bit", "bits" })
add("data", 1, "B", { "byte", "bytes" })
add("data", 1000, "kB", { "kb" })
add("data", 1000000, "MB", { "mb" })
add("data", 1000000000, "GB", { "gb" })
add("data", 1000000000000, "TB", { "tb" })
add("data", 1024, "KiB", { "kib", "kibibyte", "kibibytes" })
add("data", 1048576, "MiB", { "mib", "mebibyte", "mebibytes" })
add("data", 1073741824, "GiB", { "gib", "gibibyte", "gibibytes" })
add("data", 1099511627776, "TiB", { "tib", "tebibyte", "tebibytes" })

-- energy, base joule
add("energy", 1, "J", { "j", "joule", "joules" })
add("energy", 1000, "kJ", { "kj", "kilojoule", "kilojoules" })
add("energy", 4.184, "cal", { "cal", "calorie", "calories" })
add("energy", 4184, "kcal", { "kcal", "kilocalorie", "kilocalories" })
add("energy", 3600, "Wh", { "wh" })
add("energy", 3600000, "kWh", { "kwh" })

-- pressure, base pascal
add("pressure", 1, "Pa", { "pa", "pascal", "pascals" })
add("pressure", 1000, "kPa", { "kpa", "kilopascal", "kilopascals" })
add("pressure", 100000, "bar", { "bar", "bars" })
add("pressure", 6894.757293168, "psi", { "psi" })
add("pressure", 101325, "atm", { "atm", "atmosphere", "atmospheres" })

-- angle, base degree
add("angle", 1, "deg", { "deg", "degree", "degrees" })
add("angle", 180 / math.pi, "rad", { "rad", "radian", "radians" })
add("angle", 360, "turn", { "turn", "turns", "rev", "revs", "revolution", "revolutions" })

local function unit(name)
    if type(name) ~= "string" then return nil end
    name = trim(name)
    if name == "" then return nil end
    -- a bare b is a bit and a bare B a byte; every other name is case-insensitive
    if name == "b" then return UNITS["bit"] end
    if name == "B" then return UNITS["byte"] end
    local found = UNITS[name:lower()]
    if not found and name:sub(-1):lower() == "s" then
        found = UNITS[name:sub(1, -2):lower()]
    end
    return found
end

-- The number at the front, with an optional sign, underscores in the digits, and a dot or a comma between
-- digits as the decimal point. Returns the value and the rest of the line.
local function number_at(text)
    local sign, digits, rest = text:match("^%s*([+-]?)(%d[%d_]*[%.,]?%d*)%s*(.-)%s*$")
    if not digits then
        sign, digits, rest = text:match("^%s*([+-]?)([%.,]%d+)%s*(.-)%s*$")
    end
    if not digits then return nil end
    local value = tonumber((digits:gsub("_", ""):gsub(",", ".")))
    if not value then return nil end
    if sign == "-" then value = -value end
    return value, rest
end

-- Split the rest into the two units around to/in/as, -> or =. A word separator has to stand as its own
-- word, so the inch in "5in in cm" is not mistaken for the separator.
local function split_units(rest)
    local lower = rest:lower()
    local start, finish = lower:find("%-%>")
    if not start then
        start, finish = lower:find("=", 1, true)
    end
    for _, word in ipairs({ "to", "in", "as" }) do
        local s, e = lower:find("%s+" .. word .. "%s+")
        if s and (not start or s < start) then
            start, finish = s, e
        end
    end
    if not start then return nil end
    local from = trim(rest:sub(1, start - 1))
    local to = trim(rest:sub(finish + 1))
    if from == "" or to == "" then return nil end
    return from, to
end

function M.parse(text)
    if type(text) ~= "string" then return nil end
    if #text > 80 then return nil end
    local value, rest = number_at(text)
    if not value then return nil end
    local from, to = split_units(rest)
    if not from then return nil end
    local a, b = unit(from), unit(to)
    if not a or not b then return nil end
    return { value = value, from = a.short, to = b.short }
end

local function to_base(u, value)
    if u.short == "c" then return value + 273.15 end
    if u.short == "f" then return (value - 32) * 5 / 9 + 273.15 end
    return value * u.factor
end

local function from_base(u, value)
    if u.short == "c" then return value - 273.15 end
    if u.short == "f" then return (value - 273.15) * 9 / 5 + 32 end
    return value / u.factor
end

function M.convert(value, from, to)
    if type(value) ~= "number" then value = tonumber(value) end
    if not value or value ~= value then return nil, "not a number" end
    local a, b = unit(from), unit(to)
    if not a or not b then return nil, "unknown unit" end
    if a.kind ~= b.kind then return nil, "different kinds" end
    return from_base(b, to_base(a, value))
end

-- Up to six significant digits, plain rather than an exponent, and no trailing zeros after a point.
local function format(value)
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    if value == 0 then return "0" end
    local negative = value < 0
    local a = math.abs(value)
    local exponent = math.floor(math.log(a) / math.log(10))
    if a >= 10 ^ (exponent + 1) then exponent = exponent + 1 end
    if a < 10 ^ exponent then exponent = exponent - 1 end
    local decimals = 5 - exponent
    local out
    if decimals > 0 then
        out = string.format("%." .. decimals .. "f", a)
        out = out:gsub("0+$", ""):gsub("%.$", "")
    else
        -- a whole number larger than six digits is rounded to its first six
        local step = 10 ^ (-decimals)
        a = math.floor(a / step + 0.5) * step
        out = string.format("%.0f", a)
    end
    if out == "" then out = "0" end
    if negative then out = "-" .. out end
    return out
end

function M.answer(text)
    local parsed = M.parse(text)
    if not parsed then return nil end
    local value = M.convert(parsed.value, parsed.from, parsed.to)
    if not value then return nil end
    local shown = format(value)
    if not shown then return nil end
    return { value = value, text = shown .. " " .. parsed.to }
end

return M
