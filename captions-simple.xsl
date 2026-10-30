<?xml version="1.0" encoding="UTF-8"?>
<!--
  Annunciator captions -> XSL-FO (XSLT 1.0). Caption text is always 9pt Verdana Bold.

  <caption>       on its own: one tile, sized to its text, centred.
  <captionGroup>  a grid as authored (captionRow / captionEntry); every tile in the
                  group is as wide as the widest captionLine in the group.
  Lines are centred horizontally and vertically in each tile.
-->
<xsl:stylesheet version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:fo="http://www.w3.org/1999/XSL/Format">

  <!-- ===== Sizes (mm) ===== -->
  <xsl:variable name="pad-h"      select="2.5"/>   <!-- wriggle room left/right of the text -->
  <xsl:variable name="pad-v"      select="1"/>
  <xsl:variable name="border"     select="0.35"/>
  <xsl:variable name="gap"        select="3"/>     <!-- between tiles, across and down -->
  <xsl:variable name="min-width"  select="20"/>
  <xsl:variable name="min-height" select="10"/>

  <!-- ===== Single caption: a one-tile grid ===== -->
  <xsl:template match="caption">
    <xsl:call-template name="grid">
      <xsl:with-param name="rows"  select="."/>
      <xsl:with-param name="cols"  select="1"/>
      <xsl:with-param name="lines" select="captionLine"/>
    </xsl:call-template>
  </xsl:template>

  <!-- ===== Caption group ===== -->
  <xsl:template match="captionGroup">
    <xsl:call-template name="grid">
      <xsl:with-param name="rows"  select="captionBody/captionRow"/>
      <xsl:with-param name="cols"  select="count(colspec)"/>
      <xsl:with-param name="lines" select=".//captionLine"/>
    </xsl:call-template>
  </xsl:template>

  <!-- ===== Shared: a centred table of equal-width tiles ===== -->
  <xsl:template name="grid">
    <xsl:param name="rows"/>
    <xsl:param name="cols"/>
    <xsl:param name="lines"/>

    <xsl:variable name="text-width">
      <xsl:call-template name="widest">
        <xsl:with-param name="lines" select="$lines"/>
      </xsl:call-template>
    </xsl:variable>
    <!-- tile = text + padding + border, rounded up to 0.5mm, at least $min-width -->
    <xsl:variable name="fit" select="ceiling(($text-width + 2 * $pad-h + 2 * $border) * 2) div 2"/>
    <xsl:variable name="tile" select="$fit * ($fit &gt;= $min-width) + $min-width * ($fit &lt; $min-width)"/>

    <!-- FOP quirks: columns must include the gap, and the row minimum excludes padding/border -->
    <fo:table table-layout="fixed" width="100%" border-collapse="separate"
              border-separation="{$gap}mm" space-before="2mm" space-after="2mm">
      <fo:table-column column-width="proportional-column-width(1)"/>
      <fo:table-column column-width="{$tile + $gap}mm" number-columns-repeated="{$cols}"/>
      <fo:table-column column-width="proportional-column-width(1)"/>
      <fo:table-body>
        <xsl:for-each select="$rows">
          <fo:table-row block-progression-dimension.minimum="{$min-height - 2 * $pad-v - 2 * $border}mm">
            <fo:table-cell><fo:block/></fo:table-cell>
            <xsl:apply-templates select="self::caption | captionEntry" mode="tile"/>
            <fo:table-cell column-number="{$cols + 2}"><fo:block/></fo:table-cell>
          </fo:table-row>
        </xsl:for-each>
      </fo:table-body>
    </fo:table>
  </xsl:template>

  <!-- an entry with a caption is a lit tile; an empty entry leaves an empty slot -->
  <xsl:template match="captionEntry" mode="tile">
    <fo:table-cell><fo:block/></fo:table-cell>
  </xsl:template>
  <xsl:template match="captionEntry[caption]" mode="tile">
    <xsl:apply-templates select="caption" mode="tile"/>
  </xsl:template>

  <!-- the tile; the cell stretches to the row, so neighbours share the tallest height -->
  <xsl:template match="caption" mode="tile">
    <fo:table-cell border="{$border}mm solid black" padding="{$pad-v}mm {$pad-h}mm"
                   display-align="center">
      <xsl:attribute name="background-color">
        <xsl:call-template name="lamp-colour"/>
      </xsl:attribute>
      <xsl:for-each select="captionLine">
        <fo:block text-align="center" font-family="Verdana" font-weight="bold"
                  font-size="9pt" line-height="1.15" keep-together.within-line="always">
          <xsl:value-of select="normalize-space(.)"/>
        </fo:block>
      </xsl:for-each>
    </fo:table-cell>
  </xsl:template>

  <!-- ===== Colour codes: replace with your project's colour table ===== -->
  <xsl:template name="lamp-colour">
    <xsl:choose>
      <xsl:when test="@color = 'co01'">#9be29b</xsl:when>  <!-- green -->
      <xsl:when test="@color = 'co02'">#ffc845</xsl:when>  <!-- amber -->
      <xsl:when test="@color = 'co03'">#fff176</xsl:when>  <!-- yellow -->
      <xsl:when test="@color = 'co04'">#ff6b6b</xsl:when>  <!-- red -->
      <xsl:otherwise>#ffffff</xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- ===== Text width =====
       Verdana Bold widths (1/1000 em) grouped into classes, each rounded UP so the
       estimate never undershoots (typically 1-5% over for capitals):
       space 345 | .,: 410 | -()IJ 560 | EFL 690 | ABCKPRVXY 790 | DGHNOQU&#+ 870 |
       M 950 | W 1130 | everything else (STZ, digits, /) 720.
       Result in mm at 9pt: units/1000 * 9pt * 25.4/72. -->
  <xsl:template name="widest">
    <xsl:param name="lines"/>
    <xsl:param name="max" select="0"/>
    <xsl:choose>
      <xsl:when test="not($lines)">
        <xsl:value-of select="$max"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:variable name="s" select="normalize-space($lines[1])"/>
        <xsl:variable name="n" select="string-length($s)"/>
        <xsl:variable name="units" select="$n * 720
          - ($n - string-length(translate($s, ' ', ''))) * 375
          - ($n - string-length(translate($s, '.,:', ''))) * 310
          - ($n - string-length(translate($s, '-()IJ', ''))) * 160
          - ($n - string-length(translate($s, 'EFL', ''))) * 30
          + ($n - string-length(translate($s, 'ABCKPRVXY', ''))) * 70
          + ($n - string-length(translate($s, 'DGHNOQU&amp;#+', ''))) * 150
          + ($n - string-length(translate($s, 'M', ''))) * 230
          + ($n - string-length(translate($s, 'W', ''))) * 410"/>
        <xsl:variable name="mm" select="$units * 9 * 25.4 div 72000"/>
        <xsl:call-template name="widest">
          <xsl:with-param name="lines" select="$lines[position() &gt; 1]"/>
          <xsl:with-param name="max" select="$mm * ($mm &gt; $max) + $max * ($mm &lt;= $max)"/>
        </xsl:call-template>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

</xsl:stylesheet>
