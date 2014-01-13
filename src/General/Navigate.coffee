Navigate =
  path: window.location.pathname
  init: ->
    return if g.VIEW is 'catalog' or g.BOARD.ID is 'f'

    # blink/webkit throw a popstate on page load. Not what we want.
    $.ready -> $.on window, 'popstate', Navigate.popstate

    Thread.callbacks.push
      name: 'Navigate'
      cb:   @thread

    Post.callbacks.push
      name: 'Navigate'
      cb:   @post

  thread: ->
    return if g.VIEW is 'thread' # The reply link only exists in index view
    replyLink = $ 'a.replylink', @OP.nodes.info
    $.on replyLink, 'click', Navigate.navigate

  post: ->
    # We don't need to reload the thread inside the thread
    return if g.VIEW is 'thread' and @thread.ID is g.THREADID
    postlink = $ 'a[title="Highlight this post"]', @nodes.info
    $.on postlink, 'click', Navigate.navigate

    return unless Conf['Quote Hash Navigation']
    for hashlink in $$ '.hashlink', @nodes.comment
      $.on hashlink, 'click', Navigate.navigate
    return

  clean: ->
    {posts, threads} = g

    # Garbage collection
    g.posts         = {}
    g.threads       = {}
    g.BOARD.posts   = {}
    g.BOARD.threads = {}

    QuoteBacklink.containers = {}

    # Delete nodes
    $.rmAll $ '.board'

  features: [
    ['Thread Excerpt',   ThreadExcerpt]
    ['Unread Count',     Unread]
    ['Quote Threading',  QuoteThreading]
    ['Thread Stats',     ThreadStats]
    ['Thread Updater',   ThreadUpdater]
    ['Thread Expansion', ExpandThread]
  ]

  disconnect: ->
    for [name, feature] in Navigate.features
      try
        feature.disconnect()
      catch err
        errors = [] unless errors
        errors.push
          message: "Failed to disconnect feature #{name}."
          error:   err

      Main.handleErrors errors if errors

    return

  reconnect: ->
    for [name, feature] in Navigate.features
      try
        feature.init()
      catch err
        errors = [] unless errors
        errors.push
          message: "Failed to reconnect feature #{name}."
          error:   err
    Main.handleErrors errors if errors
    return

  ready: (name, feature, condition) ->
    try
      feature() if condition
    catch err
      error = [
        message: "Quote Threading Failed."
        error:   err
      ]
    Main.handleErrors error if error
    QR.generatePostableThreadsList()

  updateContext: (view) ->
    $.rmClass doc, g.VIEW
    $.addClass doc, view
    g.VIEW = view

    switch view
      when 'index'
        delete g.THREADID
        QR.link.textContent = 'Start a Thread'
        $.off d, 'ThreadUpdate', QR.statusCheck
        $.on  d, 'IndexRefresh', QR.generatePostableThreadsList
      when 'thread'
        g.THREADID = +window.location.pathname.split('/')[3]
        QR.link.textContent = 'Reply to Thread'
        $.on  d, 'ThreadUpdate', QR.statusCheck
        $.off d, 'IndexRefresh', QR.generatePostableThreadsList

  updateBoard: (boardID) ->
    g.BOARD = new Board boardID

    req = null

    onload = (e) ->
      if e.type is 'abort'
        req.onloadend = null
        return

      return unless req.status is 200

      board = do -> try
        for board in JSON.parse(req.response).boards
          return board if board.board is boardID

      catch err
        Main.handleErrors [
          message: "Navigation failed to update board name."
          error: err
        ]
        return false

      return unless board
      Navigate.updateTitle board

      return if Favicon.SFW is sfw = !!board.ws_board # Board SFW status hasn't changed

      findStyle = ([type, base]) ->
        style = d.cookie.match new RegExp "#{type}\_style\=([^;]+)"
        return [(if style then style[1] else base), "#{type}_style"]

      style = findStyle if sfw
        ['ws',  'Yotsuba B New']
      else
        ['nws', 'Yotsuba New']

      $.globalEval "var style_group = '#{style[1]}'"

      mainStyleSheet = $ 'link[title=switch]',        d.head
      newStyleSheet  = $ "link[title='#{style[0]}']", d.head

      Favicon.SFW = sfw
      Favicon.el.href = "//s.4cdn.org/image/favicon#{if sfw then '-ws' else ''}.ico"
      $.add d.head, Favicon.el # Changing the href alone doesn't update the icon on Firefox
      Favicon.switch()

      mainStyleSheet.href = newStyleSheet.href

      Main.setClass()

    fullBoardList   = $ '#full-board-list', Header.boardList
    $.rmClass $('.current', fullBoardList), 'current'
    $.addClass $("a[href*='/#{boardID}/']", fullBoardList), 'current'
    Header.generateBoardList Conf['boardnav'].replace /(\r\n|\n|\r)/g, ' '

    req = $.ajax '//a.4cdn.org/boards.json',
      onabort:   onload
      onloadend: onload

  updateTitle: ({board, title}) ->
    $.rm subtitle if subtitle = $ '.boardSubtitle'
    $('.boardTitle').textContent = d.title = "/#{board}/ - #{title}"

  navigate: (e) ->
    return if @hostname isnt 'boards.4chan.org' or window.location.hostname is 'rs.4chan.org' or
      (e and (e.shiftKey or (e.type is 'click' and e.button isnt 0))) # Not simply a left click

    $.addClass Index.button, 'fa-spin'

    path = @pathname.split '/'
    path.shift() if path[0] is ''
    [boardID, view, threadID] = path

    return if view is 'catalog' or 'f' in [boardID, g.BOARD.ID]
    e.preventDefault() if e

    path = @pathname
    path += @hash if @hash

    history.pushState null, '', path unless @id is 'popState'
    Navigate.path = @pathname

    if threadID
      view = 'thread'
    else
      pageNum = view
      view = 'index' # path is "/boardID/". See the problem?

    if view isnt g.VIEW
      Navigate.disconnect()
      Navigate.clean()
      Navigate.updateContext view
      Navigate.reconnect()

    if view is 'index'
      if boardID is g.BOARD.ID
        d.title = $('.boardTitle').textContent
      else
        Navigate.updateBoard boardID

      Index.update pageNum

    # Moving from index to thread or thread to thread
    else
      onload = (e) -> Navigate.load e
      Navigate.req = $.ajax "//a.4cdn.org/#{boardID}/res/#{threadID}.json",
        onabort:   onload
        onloadend: onload

      setTimeout (->
        if Navigate.req and !Navigate.notice
          Navigate.notice = new Notice 'info', 'Loading thread...'
      ), 3 * $.SECOND

  load: (e) ->
    $.rmClass Index.button, 'fa-spin'
    {req, notice} = Navigate
    notice?.close()
    delete Navigate.req
    delete Navigate.notice

    if e.type is 'abort'
      req.onloadend = null
      return

    try
      if req.status is 200
        Navigate.parse JSON.parse(req.response).posts
    catch err
      console.error 'Navigate failure:'
      console.log err
      # network error or non-JSON content for example.
      if notice
        notice.setType 'error'
        notice.el.lastElementChild.textContent = 'Navigation Failed.'
        setTimeout notice.close, 2 * $.SECOND
      else
        new Notice 'error', 'Navigation Failed.', 2
      return

  parse: (data) ->
    board = g.BOARD
    Navigate.threadRoot = threadRoot = Build.thread board, OP = data.shift(), true
    thread = new Thread OP.no, board

    posts  = []
    errors = null

    makePost = (postNode) ->
      try
        posts.push new Post postNode, thread, board
      catch err
        # Skip posts that we failed to parse.
        errors = [] unless errors
        errors.push
          message: "Parsing of Post No.#{thread.ID} failed. Post will be skipped."
          error: err

    makePost $('.opContainer', threadRoot)

    for obj in data
      post = Build.postFromObject obj, board
      makePost post
      $.add threadRoot, post

    Main.handleErrors errors if errors

    Main.callbackNodes Thread, [thread]
    Main.callbackNodes Post,   posts

    Navigate.ready 'Quote Threading', QuoteThreading.force, Conf['Quote Threading']

    Navigate.buildThread()
    Header.hashScroll.call window

  buildThread: ->
    board = $ '.board'
    $.rmAll board
    $.add board, [Navigate.threadRoot, $.el 'hr']

    if Conf['Unread Count']
      Navigate.ready 'Unread Count', Unread.ready, not Conf['Quote Threading']
      Unread.read()
      Unread.update()

  popstate: ->
    return if window.location.pathname is Navigate.path
    a = $.el 'a',
      href: window.location
      id:   'popState'

    Navigate.navigate.call a
