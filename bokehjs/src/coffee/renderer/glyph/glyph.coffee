define [
  "underscore",
  "common/logging",
  "common/has_parent",
  "common/collection"
  "common/plot_widget",
  "renderer/properties"
], (_, Logging, HasParent, Collection, PlotWidget, Properties) ->

  logger = Logging.logger

  class GlyphView extends PlotWidget

    initialize: (options) ->
      super(options)
      @props = init_props()

    init_props: ->
      props = {}

      if 'line' in @_properties
        props.line_properties = new Properties.line_properties(@, glyphspec)
      if 'fill' in @_properties
        props.fill_properties = new Properties.fill_properties(@, glyphspec)
      if 'text' in @_properties
        props.text_properties = new Properties.text_properties(@, glyphspec)

      new Properties.glyph_properties(@, glyphspec, @_fields, props)

    set_data: (request_render=true) ->
      source = @mget('data_source')

      for field in @_fields
        if field.indexOf(":") > -1
          [field, junk] = field.split(":")
        @[field] = @glyph_props.source_v_select(field, source)

        # special cases
        if field == "direction"
          values = new Uint8Array(@direction.length)
          for i in [0...@direction.length]
            dir = @direction[i]
            if      dir == 'clock'     then values[i] = false
            else if dir == 'anticlock' then values[i] = true
            else values = NaN
          @direction = values

        if field.indexOf("angle") > -1
          @[field] = (-x for x in @[field])

      # any additional customization can happen here
      if @_set_data?
        t0 = Date.now()
        @_set_data()
        dt = Date.now() - t0
        type = @mget('glyphspec').type
        id = @mget("id")
        logger.debug("#{type} glyph (#{id}): custom _set_data finished in #{dt}ms")

      # just use the length of the last added field
      len = @[field].length

      @all_indices = [0...len]

      @have_new_data = true

      if request_render
        @request_render()

    render: () ->
      if @need_set_data
        @set_data(false)
        @need_set_data = false

      @_map_data()

      if @_mask_data? and (@plot_view.x_range.type != "FactorRange") and (@plot_view.y_range.type != "FactorRange")
        indices = @_mask_data()
      else
        indices = @all_indices

      ctx = @plot_view.canvas_view.ctx
      ctx.save()

      do_render = (ctx, indices, glyph_props) =>
        source = @mget('data_source')

        if @have_new_data
          if glyph_props.fill_properties? and glyph_props.fill_properties.do_fill
            glyph_props.fill_properties.set_prop_cache(source)
          if glyph_props.line_properties? and glyph_props.line_properties.do_stroke
            glyph_props.line_properties.set_prop_cache(source)
          if glyph_props.text_properties?
            glyph_props.text_properties.set_prop_cache(source)

        @_render(ctx, indices, glyph_props)

      selected = @mget('data_source').get('selected')

      t0 = Date.now()

      if selected and selected.length and @have_selection_props()

        # reset the selection mask
        selected_mask = (false for i in @all_indices)
        for idx in selected
          selected_mask[idx] = true

        # intersect/different selection with render mask
        selected = new Array()
        nonselected = new Array()
        for i in indices
          if selected_mask[i]
            selected.push(i)
          else
            nonselected.push(i)

        do_render(ctx, selected, @selection_glyphprops)
        do_render(ctx, nonselected, @nonselection_glyphprops)

      else
        do_render(ctx, indices, @glyph_props)

      dt = Date.now() - t0
      type = @mget('glyphspec').type
      id = @mget("id")
      logger.trace("#{type} glyph (#{id}): do_render calls finished in #{dt}ms")

      @have_new_data = false

      ctx.restore()

    xrange: () ->
      return @plot_view.x_range

    yrange: () ->
      return @plot_view.y_range

    distance_vector: (pt, span_prop_name, position, dilate=false) ->
      """ returns an array """
      pt_units = @glyph_props[pt].units
      span_units = @glyph_props[span_prop_name].units

      if      pt == 'x' then mapper = @xmapper
      else if pt == 'y' then mapper = @ymapper

      source = @mget('data_source')
      local_select = (prop_name) =>
        return @glyph_props.source_v_select(prop_name, source)
      span = local_select(span_prop_name)
      if span_units == 'screen'
        return span

      if position == 'center'
        halfspan = (d / 2 for d in span)
        ptc = local_select(pt)
        if pt_units == 'screen'
          ptc = mapper.v_map_from_target(ptc)
        if typeof(ptc[0]) == 'string'
          ptc = mapper.v_map_to_target(ptc)
        pt0 = (ptc[i] - halfspan[i] for i in [0...ptc.length])
        pt1 = (ptc[i] + halfspan[i] for i in [0...ptc.length])

      else
        pt0 = local_select(pt)
        if pt_units == 'screen'
          pt0 = mapper.v_map_from_target(pt0)
        pt1 = (pt0[i] + span[i] for i in [0...pt0.length])

      spt0 = mapper.v_map_to_target(pt0)
      spt1 = mapper.v_map_to_target(pt1)

      if dilate
        return (Math.ceil(Math.abs(spt1[i] - spt0[i])) for i in [0...spt0.length])
      else
        return (Math.abs(spt1[i] - spt0[i]) for i in [0...spt0.length])

    get_reference_point: () ->
      reference_point = @mget('reference_point')
      if _.isNumber(reference_point)
        return @data[reference_point]
      else
        return reference_point

    draw_legend: (ctx, x0, x1, y0, y1) ->
      null

    _generic_line_legend: (ctx, x0, x1, y0, y1) ->
      reference_point = @get_reference_point() ? 0
      line_props = @glyph_props.line_properties
      ctx.save()
      ctx.beginPath()
      ctx.moveTo(x0, (y0 + y1) /2)
      ctx.lineTo(x1, (y0 + y1) /2)
      if line_props.do_stroke
        line_props.set_vectorize(ctx, reference_point)
        ctx.stroke()
      ctx.restore()

    _generic_area_legend: (ctx, x0, x1, y0, y1) ->
      reference_point = @get_reference_point() ? 0

      indices = [reference_point]

      w = Math.abs(x1-x0)
      dw = w*0.1
      h = Math.abs(y1-y0)
      dh = h*0.1

      sx0 = x0 + dw
      sx1 = x1 - dw

      sy0 = y0 + dh
      sy1 = y1 - dh

      if @glyph_props.fill_properties.do_fill
        @glyph_props.fill_properties.set_vectorize(ctx, reference_point)
        ctx.fillRect(sx0, sy0, sx1-sx0, sy1-sy0)

      if @glyph_props.line_properties.do_stroke
        ctx.beginPath()
        ctx.rect(sx0, sy0, sx1-sx0, sy1-sy0)
        @glyph_props.line_properties.set_vectorize(ctx, reference_point)
        ctx.stroke()

    hit_test: (geometry) ->
      result = null

      if geometry.type == "point"
        if @_hit_point?
          result = @_hit_point(geometry)
        else if not @_point_hit_warned?
          type = @mget('glyphspec').type
          logger.warn("'point' selection not available on #{type} renderer")
          @_point_hit_warned = true
      else if geometry.type == "rect"
        if @_hit_rect?
          result = @_hit_rect(geometry)
        else if not @_rect_hit_warned?
          type = @mget('glyphspec').type
          logger.warn("'rect' selection not available on #{type} renderer")
          @_rect_hit_warned = true
      else
        logger.error("unrecognized selection geometry type '#{ geometry.type }'")

      return result

  class Glyph extends HasParent

    fill_defaults: {
      fill_color: 'gray'
      fill_alpha: 1.0
    }

    line_defaults: {
      line_color: 'red'
      line_width: 1
      line_alpha: 1.0
      line_join: 'miter'
      line_cap: 'butt'
      line_dash: []
      line_dash_offset: 0
    }

  class Glyphs extends Collection

  return {
    Model: Glyph
    View: GlyphView
    Collection: Glyphs
  }
