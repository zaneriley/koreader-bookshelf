describe("Bookshelf readable measure rule", function()
    local ReadableMeasure

    setup(function()
        ReadableMeasure = dofile("plugins/bookshelf.koplugin/readablemeasure.lua")
    end)

    local function measure_text(text, _, size)
        -- a simple mock: a = 0.5. So 100 characters at size 20 is 100 * 20 * 0.5 = 1000px
        return ReadableMeasure.utf8Length(text) * size * 0.5
    end

    it("uses font_size_candidates to test discrete layouts and outputs logical size", function()
        local result = ReadableMeasure.translateToKOReaderProfile({
            reading_preset_id = "literary-latin",
            font_face = "EBGaramond-Regular.ttf",
            viewport_width_px = 1404,
            dpi = 226,
            target_cpl = 62,
            font_size_candidates = { 20, 22, 24 }, -- logical sizes
            sample_text = "You will rejoice to hear that no disaster has accompanied the commencement.",
            measure_text = measure_text,
            scale = 2,
        })

        assert.equals("pass", result.result)
        -- Since it tests candidates, let's see which one wins.
        -- We want to hit 62 CPL exactly by adjusting margins.
        -- The one that gets exactly 62 CPL with valid margins wins.
        -- Actually, the candidate search looks for the one that minimizes deviation from target_cpl.
        -- But wait, my logic forces actual CPL to be calculated based on integer margin constraints.
        -- All candidates that fit in bounds will get a score based on |estimated_cpl - target_cpl|.
        
        -- We know the exported font size should be one of the candidates in logical units.
        assert.is_true(
            result.candidate.font_size == 20 or
            result.candidate.font_size == 22 or
            result.candidate.font_size == 24
        )
        assert.equals(result.candidate.font_size, result.profile.font_size)
    end)

    it("falls back to continuous search if candidates are missing, and un-scales output", function()
        local result = ReadableMeasure.translateToKOReaderProfile({
            reading_preset_id = "literary-latin",
            font_face = "EBGaramond-Regular.ttf",
            viewport_width_px = 1404,
            dpi = 226,
            target_cpl = 62,
            target_font_size_pt = 11,
            min_margin_pt = 12,
            max_margin_pt = 72,
            sample_text = "A sample text for continuous test.",
            measure_text = measure_text,
            scale = 2,
        })

        assert.equals("pass", result.result)
        -- Best logical size search means font_size should be roughly half the engine size.
        -- The target engine size is roughly 34px, so logical size should be 17.
        assert.is_number(result.candidate.font_size)
        assert.equals(result.candidate.font_size, result.profile.font_size)
        assert.equals(result.candidate.font_size * 2, result.candidate.font_size_px)
    end)
end)
