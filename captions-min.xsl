<?xml version="1.0" encoding="UTF-8"?>
<!-- Annunciator captions -> XSL-FO (XSLT 1.0). Text is 9pt Verdana Bold. -->
<xsl:stylesheet version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:fo="http://www.w3.org/1999/XSL/Format">

  <xsl:variable name="pad"   select="2.5"/>  <!-- mm, left/right of the text -->
  <xsl:variable name="gap"   select="3"/>    <!-- mm, between tiles -->
  <xsl:variable name="min-w" select="20"/>   <!-- mm, minimum tile width -->
  <xsl:variable name="min-h" select="7.3"/>  <!-- mm, minimum text area height (10mm tile) -->
  <xsl:variable name="char"  select="2.47"/> <!-- mm, average Verdana Bold 9pt capital -->

  <xsl:template match="caption">
    <xsl:call-template name="grid">
      <xsl:with-param name="cols" select="1"/>
    </xsl:call-template>
  </xsl:template>

  <xsl:template match="captionGroup">
    <xsl:call-template name="grid">
      <xsl:with-param name="cols" select="count(colspec)"/>
    </xsl:call-template>
  </xsl:template>

  <xsl:template name="grid">
    <xsl:param name="cols"/>
    <!-- longest line, by number of characters -->
    <xsl:variable name="chars">
      <xsl:for-each select="descendant-or-self::captionLine">
        <xsl:sort select="string-length(normalize-space())" data-type="number" order="descending"/>
        <xsl:if test="position() = 1"><xsl:value-of select="string-length(normalize-space())"/></xsl:if>
      </xsl:for-each>
    </xsl:variable>
    <xsl:variable name="w" select="$chars * $char + 2 * $pad + 1"/>

    <fo:table table-layout="fixed" width="100%" border-collapse="separate" border-separation="{$gap}mm">
      <fo:table-column column-width="proportional-column-width(1)"/>
      <!-- FOP takes the gap out of each column, so add it back -->
      <fo:table-column number-columns-repeated="{$cols}"
          column-width="{$w * ($w &gt; $min-w) + $min-w * ($w &lt;= $min-w) + $gap}mm"/>
      <fo:table-column column-width="proportional-column-width(1)"/>
      <fo:table-body>
        <xsl:for-each select="self::caption | captionBody/captionRow">
          <fo:table-row block-progression-dimension.minimum="{$min-h}mm">
            <xsl:apply-templates select="self::caption | captionEntry/caption" mode="tile"/>
          </fo:table-row>
        </xsl:for-each>
      </fo:table-body>
    </fo:table>
  </xsl:template>

  <!-- column-number skips empty captionEntry slots and the left spacer column -->
  <xsl:template match="caption" mode="tile">
    <fo:table-cell column-number="{count(../preceding-sibling::captionEntry) + 2}"
        border="0.35mm solid black" padding="1mm {$pad}mm" display-align="center">
      <xsl:attribute name="background-color">
        <xsl:choose>
          <xsl:when test="@color = 'co01'">#9be29b</xsl:when>
          <xsl:when test="@color = 'co02'">#ffc845</xsl:when>
          <xsl:when test="@color = 'co03'">#fff176</xsl:when>
          <xsl:when test="@color = 'co04'">#ff6b6b</xsl:when>
          <xsl:otherwise>#ffffff</xsl:otherwise>
        </xsl:choose>
      </xsl:attribute>
      <xsl:for-each select="captionLine">
        <fo:block text-align="center" font-family="Verdana" font-weight="bold"
                  font-size="9pt" line-height="1.15" keep-together.within-line="always">
          <xsl:value-of select="normalize-space()"/>
        </fo:block>
      </xsl:for-each>
    </fo:table-cell>
  </xsl:template>

</xsl:stylesheet>
