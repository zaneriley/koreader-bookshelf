local GridLayout = {}

local COVER_RATIO_NUM = 3
local COVER_RATIO_DEN = 2

local SPECS = {
    large = {
        card_w = 148,
        card_h = 284,
        cover_w = 148,
        title_h = 32,
        metadata_h = 14,
        menu_h = 20,
        outer = 16,
        gutter = 16,
        row_gap = 24,
        max_cols = 4,
        title_size = 12,
        metadata_size = 10,
    },
    small = {
        card_w = 104,
        card_h = 208,
        cover_w = 104,
        title_h = 28,
        metadata_h = 13,
        menu_h = 18,
        outer = 16,
        gutter = 16,
        row_gap = 24,
        max_cols = 5,
        title_size = 11,
        metadata_size = 9,
    },
}

local function round(value)
    return math.floor(value + 0.5)
end

local function scaleValue(value, scale)
    return math.max(1, round(value * (scale or 1)))
end

function GridLayout.scaleValue(value, scale)
    return scaleValue(value, scale)
end

function GridLayout.scaleForViewport(width, height)
    local w = tonumber(width) or 0
    local h = tonumber(height) or 0
    if w <= 0 or h <= 0 then
        return 1
    end

    -- 672du fits a four-column large shelf. 1166du fits the current home stack
    -- with two large shelves, one small shelf, header, and bottom navigation.
    return math.max(1, math.min(w / 672, h / 1166))
end

function GridLayout.spec(kind)
    return SPECS[kind]
end

function GridLayout.metrics(kind, scale)
    local spec = assert(SPECS[kind], "unknown bookshelf grid kind: " .. tostring(kind))
    local cover_w = scaleValue(spec.cover_w, scale)
    local cover_h = scaleValue(spec.cover_w * COVER_RATIO_NUM / COVER_RATIO_DEN, scale)

    return {
        kind = kind,
        scale = scale or 1,
        card_w = scaleValue(spec.card_w, scale),
        card_h = scaleValue(spec.card_h, scale),
        cover_w = cover_w,
        cover_h = cover_h,
        title_h = scaleValue(spec.title_h, scale),
        metadata_h = scaleValue(spec.metadata_h, scale),
        menu_h = scaleValue(spec.menu_h, scale),
        outer = scaleValue(spec.outer, scale),
        gutter = scaleValue(spec.gutter, scale),
        row_gap = scaleValue(spec.row_gap, scale),
        max_cols = spec.max_cols,
        title_size = spec.title_size,
        metadata_size = spec.metadata_size,
    }
end

function GridLayout.columns(kind, width, scale)
    local metrics = GridLayout.metrics(kind, scale)
    local available = math.max(0, (tonumber(width) or 0) - metrics.outer * 2)
    if available < metrics.card_w then
        return 1
    end
    local cols = math.floor((available + metrics.gutter) / (metrics.card_w + metrics.gutter))
    return math.max(1, math.min(metrics.max_cols, cols))
end

function GridLayout.rowsForHeight(kind, height, scale)
    local metrics = GridLayout.metrics(kind, scale)
    local available = tonumber(height) or 0
    if available < metrics.card_h then
        return 0
    end
    return math.max(1, math.floor((available + metrics.row_gap) / (metrics.card_h + metrics.row_gap)))
end

function GridLayout.grid(kind, opts)
    opts = opts or {}
    local metrics = GridLayout.metrics(kind, opts.scale)
    local cols = opts.columns or GridLayout.columns(kind, opts.w, opts.scale)
    local rows = opts.rows or math.ceil(math.max(0, opts.item_count or 0) / cols)
    local item_count = math.max(0, tonumber(opts.item_count) or 0)
    local limit = math.min(item_count, cols * rows)
    local slots = {}

    for index = 1, limit do
        local col = (index - 1) % cols
        local row = math.floor((index - 1) / cols)
        local x = (opts.x or 0) + metrics.outer + col * (metrics.card_w + metrics.gutter)
        local y = (opts.y or 0) + row * (metrics.card_h + metrics.row_gap)
        local title_y = y + metrics.cover_h + scaleValue(6, opts.scale)
        local metadata_y = title_y + metrics.title_h
        local menu_size = metrics.menu_h
        slots[index] = {
            index = index,
            col = col + 1,
            row = row + 1,
            x = x,
            y = y,
            w = metrics.card_w,
            h = metrics.card_h,
            cover = {
                x = x,
                y = y,
                w = metrics.cover_w,
                h = metrics.cover_h,
            },
            title = {
                x = x + scaleValue(4, opts.scale),
                y = title_y,
                w = metrics.card_w - scaleValue(8, opts.scale),
                h = metrics.title_h,
            },
            metadata = {
                x = x + scaleValue(4, opts.scale),
                y = metadata_y,
                w = metrics.card_w - scaleValue(8, opts.scale) - menu_size,
                h = metrics.metadata_h,
            },
            menu = {
                x = x + metrics.card_w - menu_size,
                y = y + metrics.card_h - menu_size,
                w = menu_size,
                h = menu_size,
            },
        }
    end

    return {
        kind = kind,
        metrics = metrics,
        columns = cols,
        rows = rows,
        slots = slots,
        visible_count = limit,
        capacity = cols * rows,
    }
end

function GridLayout.bottomTabs(opts)
    opts = opts or {}
    local x = opts.x or 0
    local y = opts.y or 0
    local w = tonumber(opts.w) or 0
    local count = math.max(1, tonumber(opts.count) or 1)
    local scale = opts.scale
    local edge = scaleValue(16, scale)
    local content_w = math.max(0, w - edge * 2)
    local slots = {}
    local icon_size = scaleValue(24, scale)
    local top = scaleValue(10, scale)
    local bottom = scaleValue(12, scale)
    local gap = scaleValue(5, scale)
    local height = scaleValue(68, scale)
    local label_h = math.max(1, height - top - icon_size - gap - bottom)
    local label_y = y + height - bottom - label_h

    for index = 1, count do
        local slot_x = x + edge + math.floor((index - 1) * content_w / count)
        local next_x = x + edge + math.floor(index * content_w / count)
        local slot_w = math.max(1, next_x - slot_x)
        slots[index] = {
            index = index,
            x = slot_x,
            y = y,
            w = slot_w,
            h = height,
            tap = {
                x = slot_x,
                y = y,
                w = slot_w,
                h = height,
            },
            icon = {
                x = slot_x + math.floor((slot_w - icon_size) / 2),
                y = y + top,
                w = icon_size,
                h = icon_size,
            },
            label = {
                x = slot_x,
                y = label_y,
                w = slot_w,
                h = label_h,
            },
        }
    end

    return {
        x = x,
        y = y,
        w = w,
        h = height,
        edge = edge,
        top = top,
        bottom = bottom,
        icon_size = icon_size,
        icon_label_gap = gap,
        slots = slots,
    }
end

return GridLayout
