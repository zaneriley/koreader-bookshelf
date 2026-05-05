describe("Bookshelf grid layout", function()
    local GridLayout

    setup(function()
        GridLayout = dofile("plugins/bookshelf.koplugin/gridlayout.lua")
    end)

    it("renders no card slots for empty grids", function()
        local grid = GridLayout.grid("small", {
            x = 0,
            y = 0,
            w = 600,
            rows = 1,
            item_count = 0,
            scale = 1,
        })

        assert.equals(4, grid.columns)
        assert.equals(4, grid.capacity)
        assert.equals(0, #grid.slots)
    end)

    it("keeps one book in the first column without stretching", function()
        local one = GridLayout.grid("small", {
            x = 0,
            y = 0,
            w = 600,
            rows = 1,
            item_count = 1,
            scale = 1,
        })
        local full = GridLayout.grid("small", {
            x = 0,
            y = 0,
            w = 600,
            rows = 1,
            item_count = 5,
            scale = 1,
        })

        assert.equals(1, #one.slots)
        assert.equals(16, one.slots[1].x)
        assert.equals(104, one.slots[1].w)
        assert.equals(208, one.slots[1].h)
        assert.equals(full.slots[1].x, one.slots[1].x)
        assert.equals(full.slots[1].w, one.slots[1].w)
        assert.equals(full.slots[1].cover.w, one.slots[1].cover.w)
        assert.equals(full.slots[1].cover.h, one.slots[1].cover.h)
    end)

    it("left-aligns partial rows without redistributing columns", function()
        local grid = GridLayout.grid("small", {
            x = 0,
            y = 0,
            w = 600,
            rows = 1,
            item_count = 3,
            scale = 1,
        })

        assert.equals(3, #grid.slots)
        assert.equals(16, grid.slots[1].x)
        assert.equals(136, grid.slots[2].x)
        assert.equals(256, grid.slots[3].x)
        assert.equals(104, grid.slots[1].w)
        assert.equals(grid.slots[1].w, grid.slots[2].w)
        assert.equals(grid.slots[2].w, grid.slots[3].w)
    end)

    it("keeps the same fixed gutter across large and small grids", function()
        local large = GridLayout.metrics("large", 1)
        local small = GridLayout.metrics("small", 1)
        local narrow = GridLayout.grid("small", {
            x = 0,
            y = 0,
            w = 600,
            rows = 1,
            item_count = 4,
            scale = 1,
        })
        local exact_five = GridLayout.grid("small", {
            x = 0,
            y = 0,
            w = 616,
            rows = 1,
            item_count = 5,
            scale = 1,
        })

        assert.equals(16, large.gutter)
        assert.equals(large.gutter, small.gutter)
        assert.equals(4, narrow.columns)
        assert.equals(5, exact_five.columns)
        assert.equals(136, exact_five.slots[2].x)
        assert.equals(600, exact_five.slots[5].x + exact_five.slots[5].w)
    end)

    it("wraps large shelves left-to-right, then top-to-bottom", function()
        local grid = GridLayout.grid("large", {
            x = 0,
            y = 0,
            w = 672,
            rows = 2,
            item_count = 8,
            scale = 1,
        })

        assert.equals(8, #grid.slots)
        assert.equals(1, grid.slots[1].row)
        assert.equals(4, grid.slots[4].col)
        assert.equals(2, grid.slots[5].row)
        assert.equals(1, grid.slots[5].col)
        assert.equals(16, grid.slots[5].x)
        assert.equals(308, grid.slots[5].y)
    end)

    it("keeps the cover ratio constant across grid types", function()
        local large = GridLayout.metrics("large", 1)
        local small = GridLayout.metrics("small", 1)
        local large_ratio = large.cover_h / large.cover_w
        local small_ratio = small.cover_h / small.cover_w

        assert.is_true(math.abs(large_ratio - small_ratio) < 0.01)
        assert.is_true(math.abs(large_ratio - 1.5) < 0.01)
        assert.equals(148, large.cover_w)
        assert.equals(222, large.cover_h)
        assert.equals(104, small.cover_w)
        assert.equals(156, small.cover_h)
    end)

    it("lays out bottom tabs as four padded 1fr columns", function()
        local nav = GridLayout.bottomTabs({
            x = 0,
            y = 100,
            w = 600,
            count = 4,
            scale = 1,
        })

        assert.equals(68, nav.h)
        assert.equals(16, nav.edge)
        assert.equals(10, nav.top)
        assert.equals(12, nav.bottom)
        assert.equals(24, nav.icon_size)
        assert.equals(5, nav.icon_label_gap)
        assert.equals(4, #nav.slots)
        assert.equals(16, nav.slots[1].x)
        assert.equals(158, nav.slots[2].x)
        assert.equals(300, nav.slots[3].x)
        assert.equals(442, nav.slots[4].x)
        assert.equals(142, nav.slots[1].w)
        assert.equals(584, nav.slots[4].x + nav.slots[4].w)
        assert.equals(nav.slots[1].x, nav.slots[1].tap.x)
        assert.equals(nav.slots[1].y, nav.slots[1].tap.y)
        assert.equals(nav.slots[1].w, nav.slots[1].tap.w)
        assert.equals(68, nav.slots[1].tap.h)
        assert.equals(100 + 10, nav.slots[1].icon.y)
        assert.equals(100 + 10 + 24 + 5, nav.slots[1].label.y)
        assert.equals(17, nav.slots[1].label.h)
        assert.equals(100 + 68 - 12, nav.slots[1].label.y + nav.slots[1].label.h)
    end)
end)
