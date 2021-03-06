# Pane Navigator that simply replaces the active page element when it changes and cleans up the previous if it exists.
#
# @note If using Knockout, 'hasHistory', 'activePage', and 'activeUrl' methods can be can be observed for changes.
#
root = @

ACTIVE_CHECK_INTERVAL = 100
checkPanesForActivate = (pane_navigator) ->
  # check for active pane change no longer in DOM
  if active_pane = pane_navigator.activePane()
    parent_el = active_pane.el.parentNode
    while parent_el and (parent_el isnt pane_navigator.el)
      parent_el = parent_el.parentNode
    return if parent_el # still the parent
    pane_navigator.clear() # no longer active

  # check for active pane appearing
  $pane_els = $(pane_navigator.el).children().filter('.pane')
  pane_navigator.push(new kb.Pane($pane_els[0])) if $pane_els.length

class kb.PaneNavigator
  # @param [Element] el the container element for the pane navigator
  # @param [Object] options create options
  # @option options [Boolean] no_remove do not remove elements from the DOM with they are inactive. Useful if you are using a static DOM hierarchy rather than generating the elements dynamically.
  # @option options [Boolean] no_history if you would like to not store the history of panes, but only have one in memory at a time (default is with history)
  # @option options [String] transition default transition options. Either a name or `{name: 'TransitionName', option1: option2: ...}`
  constructor: (el, options) ->
    el or throwMissing(@, 'el')

    @[key] = value for key, value of options # mixin
    @panes = ko.observableArray()
    @el = if el and el.length then el[0] else el
    $(@el).addClass('pane-navigator') # ensure the 'pane-navigator' class exists for css

    # start checking the DOM for changes
    @interval = root.setInterval(=> checkPanesForActivate(@))

  destroy: ->
    root.clearInterval(@interval); @interval = null
    @el = null
    @clear({silent: true})

  clear: (options={}) ->
    # cancel the transition
    @cleanupTransition(true)

    # destroy the active pane
    active_pane.destroy(@) if (active_pane = @activePane())

    # clear silently
    array = @panes()
    panes = array.slice() # copy so triggering only happens after clearing (not for each pane)
    panes.pop() # remove the active pane, since it was destroyed
    array.splice(0, array.length) # clear

    # destroy panes
    while pane = panes.pop()
      pane.destroy(@) if pane.el

    # now trigger an update
    @panes([]) unless options.silent
    @

  activePane: -> return @paneAt(-1)
  previousPane: -> return @paneAt(-2)
  paneAt: (offset) ->
    panes = @panes()
    index = if offset < 0 then panes.length + offset else offset
    return if (index >=0 and index < panes.length) then panes[index] else null

  push: (active_pane, options={}) ->
    return unless active_pane # no pane

    # cancel the transition
    @cleanupTransition(true)
    active_pane.transition = options.transition if 'transition' of options # override transition

    # activate and store
    active_pane.ensureElement(@el)
    if options.silent then @panes().push(active_pane) else @panes.push(active_pane) # store new active pane

    # clean up previous
    previous_pane = @previousPane()
    cleaned_up = false
    clean_up_fn = =>
      return if cleaned_up; cleaned_up = true
      @cleanupTransition()

      if previous_pane
        # no history, destroy previous
        if @no_history
          panes = @panes()
          panes.splice(_.indexOf(panes, previous_pane), 1)
          previous_pane.destroy(@)

        # history, deactivate previous
        else
          previous_pane.deactivate(@)

    # create and start a transition
    if active_pane and (active_pane.transition or @transition)
      @startTransition(active_pane, previous_pane, clean_up_fn, true)
      active_pane.activate(@el)

    # clear previous now
    else
      active_pane.activate(@el)
      clean_up_fn()

    return active_pane

  pop: (options={}) ->
    previous_pane = @previousPane()
    return null unless previous_pane # no where to go back to
    previous_pane.ensureElement()

    # cancel the transition
    @cleanupTransition(true)

    # override the transition
    active_pane = @activePane()
    active_pane.transition = options.transition if 'transition' of options # override transition

    # activate or re-create the active pane (if it was uncached)
    @panes.pop()

    # destroy the active pane
    cleaned_up = false
    clean_up_fn = =>
      return if cleaned_up; cleaned_up = true
      @cleanupTransition()
      active_pane.destroy(@) if active_pane

    # create and start a transition
    if active_pane and (active_pane.transition or @transition)
      @startTransition(active_pane, previous_pane, clean_up_fn, false)
      previous_pane.activate(@el) # re-activate the pane

    # clear previous now
    else
      previous_pane.activate(@el) # re-activate the pane
      clean_up_fn()

    return previous_pane

  ####################################
  # Transition Animations
  ####################################
  # @private
  startTransition: (active_pane, previous_pane, callback, forward) ->
    return unless active_pane

    # use previous in reverse
    use_previous = active_pane.transition.options.use_previous if active_pane.transition and active_pane.transition.options
    if use_previous
      [active_pane, previous_pane] = [previous_pane, active_pane]
      forward = not forward

    # resolve the transition constructor
    transition = if active_pane.transition then active_pane.transition else @transition
    return null unless transition
    transition = {name: transition} if (typeof(transition) is 'string')
    kb.active_transitions[transition.name] or throwMissing(@, "transition #{transition.name}")

    # resolve the transition options
    options = {forward: forward}
    options[key] = value for key, value of transition # merge in options

    # inverse now so transition logic is kept simple
    if options.inverse
      [active_pane, previous_pane] = [previous_pane, active_pane]
      options.forward = not options.forward
    delete options.inverse

    # create the info
    active_pane.activate(@el) if active_pane # ensure there is an element
    previous_pane.activate(@el) if previous_pane # ensure there is an element
    info =
      container: @el
      from: if previous_pane then previous_pane.el else null
      to: if active_pane then active_pane.el else null
      callback: callback

    # save the state and set up the element
    start_state = new kb.TransitionSavedState(info)
    not info.to or $(info.to).addClass('in-transition')
    not info.from or $(info.from).addClass('in-transition')
    container_height = @el.clientHeight
    unless container_height
      container_height = if info.from then Math.max(info.to.clientHeight, info.from.clientHeight) else info.to.clientHeight
    $(@el).css({'overflow': 'hidden', height: container_height})
    @active_transition = {callback: callback, start_state: start_state, info: info}
    new kb.active_transitions[transition.name](info, options)

  # @private
  cleanupTransition: (cancel) ->
    return unless @active_transition
    transition = @active_transition; @active_transition = null
    if cancel
      not transition.info.to or $(transition.info.to).stopTransition()
      not transition.info.from or $(transition.info.from).stopTransition()
    transition.start_state.restore()
    transition.callback()

####################################
# Module
####################################
# export to modules
if (typeof(exports) isnt 'undefined')
  exports.PaneNavigator = kb.PaneNavigator