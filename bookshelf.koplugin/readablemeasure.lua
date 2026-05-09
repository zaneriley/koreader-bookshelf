local ReadableMeasure = {}

local DEFAULT_PREFERRED_CPL = { min = 62, max = 68 }
local DEFAULT_ACCEPTABLE_CPL = { min = 50, max = 78 }
local DEFAULT_MARGIN_BOUNDS = { min = 0, max = 140 }
local DEFAULT_PROFILE_ORDER = {
    "set_font",
    "font_size",
    "font_base_weight",
    "font_gamma",
    "h_page_margins",
    "line_spacing",
    "word_spacing",
    "word_expansion",
    "embedded_css",
    "embedded_fonts",
}

local function clamp(value, min_value, max_value)
    if value < min_value then
        return min_value
    end
    if value > max_value then
        return max_value
    end
    return value
end

local function round(value)
    return math.floor(value + 0.5)
end

local function copy_array(values)
    local copy = {}
    for index, value in ipairs(values or {}) do
        copy[index] = value
    end
    return copy
end

local function copy_table(values)
    local copy = {}
    for key, value in pairs(values or {}) do
        if type(value) == "table" then
            copy[key] = copy_table(value)
        else
            copy[key] = value
        end
    end
    return copy
end

local function utf8_length(text)
    text = tostring(text or "")
    local length = 0
    local index = 1
    local text_length = #text

    while index <= text_length do
        local byte = string.byte(text, index)
        if not byte then
            break
        elseif byte < 0x80 then
            index = index + 1
        elseif byte < 0xE0 then
            index = index + 2
        elseif byte < 0xF0 then
            index = index + 3
        else
            index = index + 4
        end
        length = length + 1
    end

    return length
end

local function assert_number(name, value)
    local number = tonumber(value)
    assert(number, name .. " must be a number")
    return number
end

local function normalize_range(range, fallback)
    range = range or fallback
    local normalized = {
        min = assert_number("range.min", range.min),
        max = assert_number("range.max", range.max),
    }
    assert(normalized.min <= normalized.max, "range.min must be <= range.max")
    return normalized
end

local function range_status(value, preferred, acceptable)
    if value >= preferred.min and value <= preferred.max then
        return "preferred"
    end
    if value >= acceptable.min and value <= acceptable.max then
        return "acceptable"
    end
    return "fail"
end

local function target_distance(value, target)
    return math.abs(value - target)
end

local function better_candidate(next_candidate, current)
    if not current then
        return true
    end

    local rank = {
        preferred = 1,
        acceptable = 2,
        fail = 3,
    }
    local next_rank = rank[next_candidate.measure_status] or 99
    local current_rank = rank[current.measure_status] or 99
    if next_rank ~= current_rank then
        return next_rank < current_rank
    end
    return next_candidate.distance_to_target < current.distance_to_target
end

local function linear_scale(value, scale)
    return value * (scale or 1)
end

local function inverse_linear_scale(value, scale)
    return value / (scale or 1)
end

function ReadableMeasure.utf8Length(text)
    return utf8_length(text)
end

function ReadableMeasure.averageAdvance(opts)
    opts = opts or {}
    local sample_text = assert(opts.sample_text, "sample_text is required")
    local char_count = opts.character_count or utf8_length(sample_text)
    assert(char_count > 0, "sample_text must contain at least one character")

    local width
    if opts.measured_width_px then
        width = opts.measured_width_px
    else
        assert(type(opts.measure_text) == "function", "measure_text is required")
        width = opts.measure_text(sample_text, opts.body_typeface, opts.body_size)
    end
    width = assert_number("measured_width_px", width)
    assert(width > 0, "measured_width_px must be positive")

    return width / char_count, char_count, width
end

function ReadableMeasure.measureModel(opts)
    opts = opts or {}
    local viewport_width_px = assert_number("viewport_width_px", opts.viewport_width_px)
    local left_margin_px = assert_number("rendered_left_margin_px", opts.rendered_left_margin_px or 0)
    local right_margin_px = assert_number("rendered_right_margin_px", opts.rendered_right_margin_px or left_margin_px)
    local avg_char_advance_px = opts.avg_char_advance_px

    if not avg_char_advance_px then
        avg_char_advance_px = ReadableMeasure.averageAdvance(opts)
    end
    avg_char_advance_px = assert_number("avg_char_advance_px", avg_char_advance_px)
    assert(avg_char_advance_px > 0, "avg_char_advance_px must be positive")

    local content_width_px = math.max(0, viewport_width_px - left_margin_px - right_margin_px)
    local estimated_cpl = content_width_px / avg_char_advance_px

    return {
        viewport_width_px = viewport_width_px,
        rendered_left_margin_px = left_margin_px,
        rendered_right_margin_px = right_margin_px,
        content_width_px = content_width_px,
        avg_char_advance_px = avg_char_advance_px,
        estimated_cpl = estimated_cpl,
    }
end

local function build_profile(opts, candidate)
    local profile = copy_table(opts.profile or {})
    profile.settings = profile.settings or {}
    profile.settings.name = profile.settings.name or opts.profile_name or opts.reading_preset_id
    profile.settings.order = copy_array(profile.settings.order or DEFAULT_PROFILE_ORDER)
    profile.set_font = opts.font_face
    profile.font_size = candidate.font_size
    profile.h_page_margins = { candidate.margin_setting, candidate.margin_setting }
    profile.line_spacing = opts.line_spacing
    profile.font_base_weight = opts.font_base_weight
    profile.font_gamma = opts.font_gamma
    profile.word_spacing = opts.word_spacing
    profile.word_expansion = opts.word_expansion
    profile.embedded_css = opts.embedded_css
    profile.embedded_fonts = opts.embedded_fonts
    return profile
end

function ReadableMeasure.translateToKOReaderProfile(opts)
    opts = opts or {}
    local viewport_width_px = assert_number("viewport_width_px", opts.viewport_width_px)
    local target_cpl = assert_number("target_cpl", opts.target_cpl or 64)
    local preferred = normalize_range(opts.preferred_cpl, DEFAULT_PREFERRED_CPL)
    local acceptable = normalize_range(opts.acceptable_cpl, DEFAULT_ACCEPTABLE_CPL)
    local margin_bounds = normalize_range(opts.margin_bounds, DEFAULT_MARGIN_BOUNDS)
    local scale = opts.scale or 1
    local scale_by_size = opts.scale_by_size or function(value) return linear_scale(value, scale) end
    local inverse_scale_by_size = opts.inverse_scale_by_size or function(value) return inverse_linear_scale(value, scale) end
    local font_size_candidates = opts.font_size_candidates or { assert_number("body_size", opts.body_size) }
    local best

    assert(opts.font_face, "font_face is required")
    assert(#font_size_candidates > 0, "font_size_candidates must not be empty")

    for _, font_size in ipairs(font_size_candidates) do
        font_size = assert_number("font_size candidate", font_size)
        local avg_char_advance_px = ReadableMeasure.averageAdvance({
            sample_text = opts.sample_text,
            character_count = opts.character_count,
            body_typeface = opts.font_face,
            body_size = font_size,
            measure_text = opts.measure_text,
            measured_width_px = opts.measured_width_px,
        })
        local target_width_px = target_cpl * avg_char_advance_px
        local requested_margin_px = (viewport_width_px - target_width_px) / 2
        local requested_margin_setting = inverse_scale_by_size(requested_margin_px)
        local clamped_margin_setting = clamp(
            round(requested_margin_setting),
            margin_bounds.min,
            margin_bounds.max
        )
        local rendered_margin_px = scale_by_size(clamped_margin_setting)
        local model = ReadableMeasure.measureModel({
            viewport_width_px = viewport_width_px,
            rendered_left_margin_px = rendered_margin_px,
            rendered_right_margin_px = rendered_margin_px,
            avg_char_advance_px = avg_char_advance_px,
        })
        local status = range_status(model.estimated_cpl, preferred, acceptable)
        local candidate = {
            font_size = font_size,
            target_cpl = target_cpl,
            target_width_px = target_width_px,
            requested_margin_px = requested_margin_px,
            requested_margin_setting = requested_margin_setting,
            margin_setting = clamped_margin_setting,
            rendered_margin_px = rendered_margin_px,
            avg_char_advance_px = avg_char_advance_px,
            content_width_px = model.content_width_px,
            estimated_cpl = model.estimated_cpl,
            measure_status = status,
            distance_to_target = target_distance(model.estimated_cpl, target_cpl),
        }

        if better_candidate(candidate, best) then
            best = candidate
        end
    end

    local result = {
        reading_preset_id = opts.reading_preset_id,
        font_candidate = opts.font_candidate,
        target_cpl = target_cpl,
        preferred_cpl = preferred,
        acceptable_cpl = acceptable,
        candidate = best,
        profile = build_profile(opts, best),
    }

    if best.measure_status == "fail" then
        result.result = "fail"
        result.failure_owner = "Reading Preset tuning"
    elseif best.measure_status == "acceptable" then
        result.result = "needs-followup"
        result.failure_owner = nil
    else
        result.result = "pass"
        result.failure_owner = nil
    end

    return result
end

return ReadableMeasure
