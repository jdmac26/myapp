<?xml version="1.0" encoding="UTF-8"?>
<!--
  Annunciator captions for XSL-FO - XSLT 1.0 version.
  Tested with Apache FOP 2.8 using xsltproc (libxslt) and the JDK's built-in XSLT processor.

  Every tile in a <captionGroup> gets the same width, worked out from the widest
  <captionLine> in the group, never narrower than $min-width-mm. Rows hold up to
  $cols-max tiles; each row is centred, so a partial last row sits in the middle.
  Tiles are at least $min-height-mm tall and grow for extra lines.

  Text width is estimated from Helvetica-Bold glyph widths (AFM units per 1000 em).
  If your captions use another font, replace the <f:g> table with that font's widths.
-->
<xsl:stylesheet version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:fo="http://www.w3.org/1999/XSL/Format"
    xmlns:f="urn:local:captions"
    exclude-result-prefixes="f">

  <xsl:output method="xml" indent="yes"/>

  <!-- ===== Tuning ===== -->
  <xsl:param name="cols-max"       select="4"/>     <!-- tiles per row -->
  <xsl:param name="font-family"    select="'Helvetica'"/>
  <xsl:param name="font-size-pt"   select="8"/>
  <xsl:param name="pad-h-mm"       select="2.5"/>   <!-- wriggle room left/right -->
  <xsl:param name="pad-v-mm"       select="1"/>
  <xsl:param name="border-mm"      select="0.35"/>  <!-- ~1pt -->
  <xsl:param name="min-width-mm"   select="20"/>
  <xsl:param name="min-height-mm"  select="10"/>
  <xsl:param name="gap-mm"         select="3"/>     <!-- between tiles and rows -->
  <xsl:param name="tile-colour"    select="'#fff3c4'"/>
  <!-- Width available to the group: region-body width minus any indents around it.
       Rows drop to fewer tiles when $cols-max tiles would not fit. -->
  <xsl:param name="avail-width-mm" select="183.5"/>

  <!-- ===== Helvetica-Bold advance widths, 1/1000 em ===== -->
  <xsl:variable name="default-glyph" select="611"/>
  <f:glyphs>
    <f:g c="A" w="722"/><f:g c="B" w="722"/><f:g c="C" w="722"/><f:g c="D" w="722"/>
    <f:g c="E" w="667"/><f:g c="F" w="611"/><f:g c="G" w="778"/><f:g c="H" w="722"/>
    <f:g c="I" w="278"/><f:g c="J" w="556"/><f:g c="K" w="722"/><f:g c="L" w="611"/>
    <f:g c="M" w="833"/><f:g c="N" w="722"/><f:g c="O" w="778"/><f:g c="P" w="667"/>
    <f:g c="Q" w="778"/><f:g c="R" w="722"/><f:g c="S" w="667"/><f:g c="T" w="611"/>
    <f:g c="U" w="722"/><f:g c="V" w="667"/><f:g c="W" w="944"/><f:g c="X" w="667"/>
    <f:g c="Y" w="667"/><f:g c="Z" w="611"/>
    <f:g c="a" w="556"/><f:g c="b" w="611"/><f:g c="c" w="556"/><f:g c="d" w="611"/>
    <f:g c="e" w="556"/><f:g c="f" w="333"/><f:g c="g" w="611"/><f:g c="h" w="611"/>
    <f:g c="i" w="278"/><f:g c="j" w="278"/><f:g c="k" w="556"/><f:g c="l" w="278"/>
    <f:g c="m" w="889"/><f:g c="n" w="611"/><f:g c="o" w="611"/><f:g c="p" w="611"/>
    <f:g c="q" w="611"/><f:g c="r" w="389"/><f:g c="s" w="556"/><f:g c="t" w="333"/>
    <f:g c="u" w="611"/><f:g c="v" w="556"/><f:g c="w" w="778"/><f:g c="x" w="556"/>
    <f:g c="y" w="556"/><f:g c="z" w="500"/>
    <f:g c="0" w="556"/><f:g c="1" w="556"/><f:g c="2" w="556"/><f:g c="3" w="556"/>
    <f:g c="4" w="556"/><f:g c="5" w="556"/><f:g c="6" w="556"/><f:g c="7" w="556"/>
    <f:g c="8" w="556"/><f:g c="9" w="556"/>
    <f:g c=" " w="278"/><f:g c="-" w="333"/><f:g c="/" w="278"/><f:g c="." w="278"/>
    <f:g c="," w="278"/><f:g c=":" w="333"/><f:g c="&amp;" w="722"/><f:g c="(" w="333"/>
    <f:g c=")" w="333"/><f:g c="+" w="584"/><f:g c="%" w="889"/><f:g c="#" w="556"/>
    <f:g c="°" w="400"/>
  </f:glyphs>
  <xsl:variable name="glyphs" select="document('')/*/f:glyphs/f:g"/>

  <!-- Width of a string in glyph units (1/1000 em): one character per recursion -->
  <xsl:template name="text-units">
    <xsl:param name="s"/>
    <xsl:param name="acc" select="0"/>
    <xsl:choose>
      <xsl:when test="$s = ''">
        <xsl:value-of select="$acc"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:variable name="g" select="$glyphs[@c = substring($s, 1, 1)]/@w"/>
        <xsl:variable name="w">
          <xsl:choose>
            <xsl:when test="$g"><xsl:value-of select="$g"/></xsl:when>
            <xsl:otherwise><xsl:value-of select="$default-glyph"/></xsl:otherwise>
          </xsl:choose>
        </xsl:variable>
        <xsl:call-template name="text-units">
          <xsl:with-param name="s" select="substring($s, 2)"/>
          <xsl:with-param name="acc" select="$acc + $w"/>
        </xsl:call-template>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- Widest line, in glyph units, across a node-set of captionLines -->
  <xsl:template name="max-units">
    <xsl:param name="lines"/>
    <xsl:param name="max" select="0"/>
    <xsl:choose>
      <xsl:when test="not($lines)">
        <xsl:value-of select="$max"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:variable name="w">
          <xsl:call-template name="text-units">
            <xsl:with-param name="s" select="normalize-space($lines[1])"/>
          </xsl:call-template>
        </xsl:variable>
        <xsl:call-template name="max-units">
          <xsl:with-param name="lines" select="$lines[position() &gt; 1]"/>
          <xsl:with-param name="max">
            <xsl:choose>
              <xsl:when test="number($w) &gt; $max"><xsl:value-of select="$w"/></xsl:when>
              <xsl:otherwise><xsl:value-of select="$max"/></xsl:otherwise>
            </xsl:choose>
          </xsl:with-param>
        </xsl:call-template>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- ===== Caption group → one centred table per row ===== -->
  <xsl:template match="captionGroup">
    <xsl:variable name="caps" select="caption"/>

    <xsl:variable name="widest-units">
      <xsl:call-template name="max-units">
        <xsl:with-param name="lines" select="$caps/captionLine"/>
      </xsl:call-template>
    </xsl:variable>
    <xsl:variable name="widest-mm" select="$widest-units div 1000 * $font-size-pt * 25.4 div 72"/>

    <!-- visible tile = text + padding + borders, rounded up to 0.5mm, never below the minimum -->
    <xsl:variable name="fit-mm"
        select="ceiling(($widest-mm + 2 * $pad-h-mm + 2 * $border-mm) * 2) div 2"/>
    <xsl:variable name="tile-mm">
      <xsl:choose>
        <xsl:when test="$fit-mm &gt; $min-width-mm"><xsl:value-of select="$fit-mm"/></xsl:when>
        <xsl:otherwise><xsl:value-of select="$min-width-mm"/></xsl:otherwise>
      </xsl:choose>
    </xsl:variable>
    <!-- FOP takes the border-separation out of each column, so add it back -->
    <xsl:variable name="col-mm" select="$tile-mm + $gap-mm"/>

    <!-- tiles per row = smallest of: captions in the group, $cols-max, how many fit (at least 1) -->
    <xsl:variable name="fit-cols" select="floor($avail-width-mm div $col-mm)"/>
    <xsl:variable name="cols">
      <xsl:choose>
        <xsl:when test="$fit-cols &lt; 1">1</xsl:when>
        <xsl:when test="$fit-cols &lt; $cols-max and $fit-cols &lt; count($caps)">
          <xsl:value-of select="$fit-cols"/>
        </xsl:when>
        <xsl:when test="count($caps) &lt; $cols-max"><xsl:value-of select="count($caps)"/></xsl:when>
        <xsl:otherwise><xsl:value-of select="$cols-max"/></xsl:otherwise>
      </xsl:choose>
    </xsl:variable>
    <xsl:if test="$fit-cols &lt; 1">
      <xsl:message>captions: a captionLine is wider than the available width (<xsl:value-of
        select="$tile-mm"/>mm tile, <xsl:value-of select="$avail-width-mm"/>mm available)</xsl:message>
    </xsl:if>
    <!-- FOP applies the row minimum to the cell content, so take off padding and borders -->
    <xsl:variable name="row-min-mm"
        select="round(($min-height-mm - 2 * $pad-v-mm - 2 * $border-mm) * 100) div 100"/>

    <fo:block space-before="4mm" space-after="4mm" keep-together.within-page="always">
      <!-- first caption of each row, then it plus the next ($cols - 1) siblings -->
      <xsl:for-each select="$caps[position() mod $cols = 1 or $cols = 1]">
        <xsl:variable name="row" select=". | following-sibling::caption[position() &lt; $cols]"/>
        <fo:table table-layout="fixed" width="100%"
                  border-collapse="separate"
                  border-separation.inline-progression-direction="{$gap-mm}mm"
                  border-separation.block-progression-direction="0mm">
          <xsl:if test="position() &gt; 1">
            <xsl:attribute name="space-before"><xsl:value-of select="$gap-mm"/>mm</xsl:attribute>
          </xsl:if>
          <fo:table-column column-width="proportional-column-width(1)"/>
          <fo:table-column column-width="{$col-mm}mm" number-columns-repeated="{count($row)}"/>
          <fo:table-column column-width="proportional-column-width(1)"/>
          <fo:table-body>
            <fo:table-row block-progression-dimension.minimum="{$row-min-mm}mm">
              <fo:table-cell><fo:block/></fo:table-cell>
              <xsl:apply-templates select="$row"/>
              <fo:table-cell><fo:block/></fo:table-cell>
            </fo:table-row>
          </fo:table-body>
        </fo:table>
      </xsl:for-each>
    </fo:block>
  </xsl:template>

  <!-- ===== One light ===== -->
  <xsl:template match="caption">
    <fo:table-cell border="{$border-mm}mm solid black"
                   background-color="{$tile-colour}"
                   padding-left="{$pad-h-mm}mm" padding-right="{$pad-h-mm}mm"
                   padding-top="{$pad-v-mm}mm" padding-bottom="{$pad-v-mm}mm"
                   display-align="center">
      <xsl:apply-templates select="captionLine"/>
    </fo:table-cell>
  </xsl:template>

  <xsl:template match="captionLine">
    <fo:block text-align="center" font-family="{$font-family}"
              font-size="{$font-size-pt}pt" font-weight="bold"
              line-height="1.15" keep-together.within-line="always">
      <xsl:value-of select="normalize-space(.)"/>
    </fo:block>
  </xsl:template>

  <!-- ===== Test harness only: page setup with mirrored 16.5/10mm margins ===== -->
  <xsl:template match="/doc">
    <fo:root>
      <fo:layout-master-set>
        <fo:simple-page-master master-name="odd" page-width="210mm" page-height="297mm"
            margin-top="15mm" margin-bottom="15mm" margin-left="16.5mm" margin-right="10mm">
          <fo:region-body/>
        </fo:simple-page-master>
        <fo:simple-page-master master-name="even" page-width="210mm" page-height="297mm"
            margin-top="15mm" margin-bottom="15mm" margin-left="10mm" margin-right="16.5mm">
          <fo:region-body/>
        </fo:simple-page-master>
        <fo:page-sequence-master master-name="mirrored">
          <fo:repeatable-page-master-alternatives>
            <fo:conditional-page-master-reference master-reference="odd" odd-or-even="odd"/>
            <fo:conditional-page-master-reference master-reference="even" odd-or-even="even"/>
          </fo:repeatable-page-master-alternatives>
        </fo:page-sequence-master>
      </fo:layout-master-set>
      <fo:page-sequence master-reference="mirrored">
        <fo:flow flow-name="xsl-region-body" font-family="Helvetica" font-size="10pt">
          <xsl:apply-templates/>
        </fo:flow>
      </fo:page-sequence>
    </fo:root>
  </xsl:template>

  <xsl:template match="para">
    <fo:block space-before="3mm"><xsl:apply-templates/></fo:block>
  </xsl:template>

</xsl:stylesheet>
