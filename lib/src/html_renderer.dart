// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';
import 'dart:convert';

import 'ast.dart';
import 'block_parser.dart';
import 'document.dart';
import 'extension_set.dart';
import 'inline_parser.dart';

/// Converts the given string of Markdown to HTML.
String markdownToHtml(String markdown,
    {Iterable<BlockSyntax> blockSyntaxes,
    Iterable<InlineSyntax> inlineSyntaxes,
    ExtensionSet extensionSet,
    Resolver linkResolver,
    Resolver imageLinkResolver,
    bool inlineOnly = false, bool checkable = false}) {
  var document = Document(
      blockSyntaxes: blockSyntaxes,
      inlineSyntaxes: inlineSyntaxes,
      extensionSet: extensionSet,
      linkResolver: linkResolver,
      imageLinkResolver: imageLinkResolver,
      checkable: checkable);

  if (inlineOnly) return renderToHtml(document.parseInline(markdown));

  // Replace windows line endings with unix line endings, and split.
  var lines = markdown.replaceAll('\r\n', '\n').split('\n');

  return renderToHtml(document.parseLines(lines)) + '\n';
}

/// Renders [nodes] to HTML.
String renderToHtml(List<Node> nodes) => HtmlRenderer().render(nodes);

const _blockTags = {
  'blockquote',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'hr',
  'p',
  'pre',
}, _listTags = {
  'li',
  'ol',
  'ul',
};

/// Translates a parsed AST to HTML.
///
/// Unlike [HtmlRenderer], it doesn't generate linefeeds among `ul`, `li`,
/// and `ul` tags. Thus, the caller can apply `white-space: pre-wrap`
/// and similar styles safely.
class CondensedHtmlRenderer implements NodeVisitor {
  StringBuffer buffer;
  Set<String> uniqueIds;

  final _elementStack = <Element>[];
  String _lastVisitedTag;

  CondensedHtmlRenderer();

  String render(List<Node> nodes) {
    buffer = StringBuffer();
    uniqueIds = LinkedHashSet<String>();

    for (final node in nodes) {
      node.accept(this);
    }

    return buffer.toString();
  }

  void visitText(Text text) {
    var content = text.text;
    if (const {'p', 'li'}.contains(_lastVisitedTag)) {
      var lines = LineSplitter.split(content);
      content = (content.contains('<pre>'))
          ? lines.join('\n')
          : lines.map((line) => line.trimLeft()).join('\n');
      if (text.text.endsWith('\n')) {
        content = '$content\n';
      }
    }
    buffer.write(content);

    _lastVisitedTag = null;
  }

  bool visitElementBefore(Element element) {
    // Hackish. Separate block-level elements with newlines.
    if (buffer.isNotEmpty && _isBlockTag(element.tag)) {
      buffer.writeln();
    }

    buffer.write('<${element.tag}');

    for (var entry in element.attributes.entries) {
      buffer.write(' ${entry.key}="${entry.value}"');
    }

    // attach header anchor ids generated from text
    if (element.generatedId != null) {
      buffer.write(' id="${uniquifyId(element.generatedId)}"');
    }

    _lastVisitedTag = element.tag;

    if (element.isEmpty) {
      // Empty element like <hr/>.
      buffer.write(' />');

      if (element.tag == 'br') {
        buffer.writeln();
      }

      return false;
    } else {
      _elementStack.add(element);
      buffer.write('>');
      return true;
    }
  }

  void visitElementAfter(Element element) {
    assert(identical(_elementStack.last, element));

    if (element.children != null &&
        element.children.isNotEmpty &&
        _isBlockTag(_lastVisitedTag) &&
        _isBlockTag(element.tag)) {
      buffer.writeln();
    } else if (element.tag == 'blockquote') {
      buffer.writeln();
    }
    buffer.write('</${element.tag}>');

    _lastVisitedTag = _elementStack.removeLast().tag;
  }

  /// Uniquifies an id generated from text.
  String uniquifyId(String id) {
    if (!uniqueIds.contains(id)) {
      uniqueIds.add(id);
      return id;
    }

    var suffix = 2;
    var suffixedId = '$id-$suffix';
    while (uniqueIds.contains(suffixedId)) {
      suffixedId = '$id-${suffix++}';
    }
    uniqueIds.add(suffixedId);
    return suffixedId;
  }

  bool _isBlockTag(String tag) => _blockTags.contains(tag);
}

/// Translates a parsed AST to HTML.
class HtmlRenderer extends CondensedHtmlRenderer {
  HtmlRenderer();

  @override
  bool _isBlockTag(String tag)
  => _blockTags.contains(tag) || _listTags.contains(tag);
}
