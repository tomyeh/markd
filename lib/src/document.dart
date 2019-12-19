// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'ast.dart';
import 'block_parser.dart';
import 'extension_set.dart';
import 'inline_parser.dart';

typedef BlockParser _BlockParserBuilder(List<String> lines, Document document);
typedef InlineParser _InlineParserBuilder(String text, Document document);

/// Maintains the context needed to parse a Markdown document.
class Document {
  final Map<String, LinkReference> linkReferences = <String, LinkReference>{};
  final ExtensionSet extensionSet;
  final Resolver linkResolver;
  final Resolver imageLinkResolver;
  final bool encodeHtml, checkable;
  /// Whether to disable the generation of nested lists for empty content,
  /// such as `* * A`.
  /// If false (default), `<ul><li><ul><li>A</li></ul></li></ul>`
  /// will be generated.
  /// If true, `<ul><li>* A</li> wll be generated instead.
  final bool emptyListDisabled;
  final _blockSyntaxes = <BlockSyntax>{};
  final _inlineSyntaxes = <InlineSyntax>{};

  Iterable<BlockSyntax> get blockSyntaxes => _blockSyntaxes;

  Iterable<InlineSyntax> get inlineSyntaxes => _inlineSyntaxes;

  ///An application specific instance.
  final dynamic options;
  ///Encapsultes the instantiation of parsers for easy customization (tom)
  final _BlockParserBuilder _blockParserBuilder;
  final _InlineParserBuilder _inlineParserBuilder;

  Document({
    Iterable<BlockSyntax> blockSyntaxes,
    Iterable<InlineSyntax> inlineSyntaxes,
    ExtensionSet extensionSet,
    this.linkResolver,
    this.imageLinkResolver,
    _BlockParserBuilder blockParserBuilder = _newBlockParser,
    _InlineParserBuilder inlineParserBuilder = _newInlineParser,
    this.options,
    this.encodeHtml = true,
    this.checkable = false,
    this.emptyListDisabled = false
  }) : extensionSet = extensionSet ?? ExtensionSet.commonMark,
      _blockParserBuilder = blockParserBuilder,
      _inlineParserBuilder = inlineParserBuilder {
    _blockSyntaxes
      ..addAll(blockSyntaxes ?? [])
      ..addAll(this.extensionSet.blockSyntaxes);
    _inlineSyntaxes
      ..addAll(inlineSyntaxes ?? [])
      ..addAll(this.extensionSet.inlineSyntaxes);
  }
  ///A lightweight, full-customized document.
  Document.plain(
      this._blockParserBuilder, this._inlineParserBuilder,
      {this.extensionSet, this.linkResolver, this.imageLinkResolver,
       this.options, this.encodeHtml = true, this.checkable = false,
       this.emptyListDisabled = false});

  BlockParser getBlockParser(List<String> lines)
  => _blockParserBuilder(lines, this);
  InlineParser getInlineParser(String text)
  => _inlineParserBuilder(text, this);

  /// Parses the given [lines] of Markdown to a series of AST nodes.
  List<Node> parseLines(List<String> lines, [int offset=0]) {
    var parser = getBlockParser(lines)..offset = offset;
    var nodes = parser.parseLines();
    _parseInlineContent(nodes);
    return nodes;
  }

  /// Parses the given inline Markdown [text] to a series of AST nodes.
  List<Node> parseInline(String text) => getInlineParser(text).parse();

  void _parseInlineContent(List<Node> nodes) {
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i];
      if (node is UnparsedContent) {
        var inlineNodes = parseInline(node.textContent);
        nodes.removeAt(i);
        nodes.insertAll(i, inlineNodes);
        i += inlineNodes.length - 1;
      } else if (node is Element && node.children != null) {
        _parseInlineContent(node.children);
      }
    }
  }
}

BlockParser _newBlockParser(List<String> lines, Document document)
=> BlockParser(lines, document);
InlineParser _newInlineParser(String text, Document document)
=> InlineParser(text, document);

/// A [link reference
/// definition](http://spec.commonmark.org/0.28/#link-reference-definitions).
class LinkReference {
  /// The [link label](http://spec.commonmark.org/0.28/#link-label).
  ///
  /// Temporarily, this class is also being used to represent the link data for
  /// an inline link (the destination and title), but this should change before
  /// the package is released.
  final String label;

  /// The [link destination](http://spec.commonmark.org/0.28/#link-destination).
  final String destination;

  /// The [link title](http://spec.commonmark.org/0.28/#link-title).
  final String title;

  /// Construct a new [LinkReference], with all necessary fields.
  ///
  /// If the parsed link reference definition does not include a title, use
  /// `null` for the [title] parameter.
  LinkReference(this.label, this.destination, this.title);
}
