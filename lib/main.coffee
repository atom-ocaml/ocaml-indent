{CompositeDisposable, BufferedProcess} = require 'atom'
{dirname} = require('path')

module.exports =
  subscriptions: null

  activate: (state) ->
    @subscriptions = new CompositeDisposable

    target = 'atom-text-editor[data-grammar~="ocaml"]'
    @subscriptions.add atom.commands.add target,
      'ocaml-indent:selection': => @indentSelection()
      'ocaml-indent:file': => @indentFile()

    @subscriptions.add atom.workspace.observeTextEditors (editor) =>
      didInsertTextDisposable = null
      @subscriptions.add editor.observeGrammar (grammar) =>
        if didInsertTextDisposable?
          @subscriptions.remove didInsertTextDisposable
          didInsertTextDisposable.dispose()
          didInsertTextDisposable = null
        return unless ['source.ocaml', 'ocaml'].includes grammar.scopeName
        didInsertTextDisposable = editor.onDidInsertText ({text, range}) =>
          if text.endsWith '\n'
            @indentNewline editor, range
          prefix = editor.getTextInBufferRange [[range.end.row, 0], range.end]
          if prefix.match /(else|then|do|and|end|done|\)|\}|\]|\|)$/
            @indentRange editor, range
        @subscriptions.add didInsertTextDisposable

  indentRange: (editor, {start, end}, text) ->
    args = ['--numeric', '--lines', "#{start.row + 1}-#{end.row + 1}"]
    text ?= editor.getText()
    cwd = if editor.getPath()?
      dirname editor.getPath()
    else
      atom.project.getPaths()[0]
    @ocpIndent args, text, cwd
    .then (output) =>
      indents = (parseInt s for s in output.trim().split '\n')
      @doIndents editor, start.row, indents

  indentNewline: (editor, range) ->
    text = editor.getTextInBufferRange [[0, 0], range.end]
    line = editor.lineTextForBufferRow range.end.row
    text += if line.trim().length then line else "(**)"
    @indentRange editor, range, text

  indentSelection: ->
    return unless editor = atom.workspace.getActiveTextEditor()
    for range in editor.getSelectedBufferRanges()
      @indentRange editor, range

  indentFile: (editor) ->
    return unless editor ?= atom.workspace.getActiveTextEditor()
    @indentRange editor, editor.getBuffer().getRange()

  ocpIndent: (args, text, cwd) ->
    new Promise (resolve, reject) ->
      command = atom.config.get 'ocaml-indent.ocpIndentPath'
      args = args.concat atom.config.get 'ocaml-indent.ocpIndentArgs'
      stdout = (output) -> resolve output
      exit = (code) -> reject code if code
      options = {cwd}
      bp = new BufferedProcess {command, args, stdout, exit, options}
      bp.process.stdin.write text
      bp.process.stdin.end()

  doIndents: (editor, startRow, indents) ->
    editor.transact 100, ->
      for indent, i in indents
        row = startRow + i
        col = editor.lineTextForBufferRow(row)?.match(/^\s*/)[0].length ? 0
        indentString =  " ".repeat indent
        editor.setTextInBufferRange([[row, 0], [row, col]], indentString)

  provideIndent: ->
    indentFile: (editor) => @indentFile editor
    indentRange: (editor, range) => @indentRange editor, range

  deactivate: ->
    @subscriptions.dispose()
