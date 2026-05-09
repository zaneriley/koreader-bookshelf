describe("Bookshelf readable measure rule", function()
    local ReadableMeasure

    setup(function()
        ReadableMeasure = dofile("plugins/bookshelf.koplugin/readablemeasure.lua")
    end)

    local function measure_text(text, _, size)
        return ReadableMeasure.utf8Length(text) * size * 0.5
    end

    it("estimates rendered characters per line from content width and font advance", function()
        local model = ReadableMeasure.measureModel({
            viewport_width_px = 1404,
            rendered_left_margin_px = 254,
            rendered_right_margin_px = 254,
            avg_char_advance_px = 14,
        })

        assert.equals(896, model.content_width_px)
        assert.is_true(math.abs(model.estimated_cpl - 64) < 0.001)
    end)

    it("translates the readable measure target into KOReader profile settings", function()
        local result = ReadableMeasure.translateToKOReaderProfile({
            reading_preset_id = "literary-latin",
            profile_name = "Literary Classic",
            font_candidate = "EB Garamond",
            font_face = "EB Garamond",
            body_size = 28,
            viewport_width_px = 1404,
            target_cpl = 64,
            sample_text = "You will rejoice to hear that no disaster has accompanied the commencement.",
            measure_text = measure_text,
            scale = 2,
            line_spacing = 120,
            font_base_weight = 0,
            font_gamma = 15,
            word_spacing = { 95, 75 },
            word_expansion = 0,
            embedded_css = 1,
            embedded_fonts = 1,
        })

        assert.equals("pass", result.result)
        assert.equals("preferred", result.candidate.measure_status)
        assert.equals(127, result.candidate.margin_setting)
        assert.equals(254, result.candidate.rendered_margin_px)
        assert.equals("Literary Classic", result.profile.settings.name)
        assert.equals("EB Garamond", result.profile.set_font)
        assert.equals(28, result.profile.font_size)
        assert.are.same({ 127, 127 }, result.profile.h_page_margins)
        assert.equals(120, result.profile.line_spacing)
        assert.are.same({ 95, 75 }, result.profile.word_spacing)
    end)

    it("chooses a larger font size when margin clamps cannot reach the target", function()
        local result = ReadableMeasure.translateToKOReaderProfile({
            reading_preset_id = "literary-latin",
            profile_name = "Literary Classic",
            font_face = "EB Garamond",
            viewport_width_px = 1404,
            target_cpl = 64,
            sample_text = "Long enough sample text for measuring a typical literary texture.",
            measure_text = measure_text,
            scale = 2,
            margin_bounds = { min = 0, max = 140 },
            font_size_candidates = { 16, 28 },
        })

        assert.equals("pass", result.result)
        assert.equals(28, result.candidate.font_size)
        assert.equals("preferred", result.candidate.measure_status)
        assert.equals(127, result.candidate.margin_setting)
    end)

    it("routes impossible measure candidates back to reading preset tuning", function()
        local result = ReadableMeasure.translateToKOReaderProfile({
            reading_preset_id = "literary-latin",
            profile_name = "Literary Classic",
            font_face = "EB Garamond",
            viewport_width_px = 500,
            target_cpl = 64,
            sample_text = "A sample text.",
            measure_text = measure_text,
            scale = 2,
            margin_bounds = { min = 0, max = 10 },
            font_size_candidates = { 40 },
        })

        assert.equals("fail", result.result)
        assert.equals("Reading Preset tuning", result.failure_owner)
        assert.equals("fail", result.candidate.measure_status)
    end)
end)
