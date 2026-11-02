You don't need to replace your templates. Each piece of the draft belongs in one of the templates you already have, so the job is adding a few attributes to each. Below is where each piece goes. I haven't seen your templates, so adjust names to match.  
**One shared helper:** the tile column width, computed from the group.  
```
<!-- context node: the captionGroup (or a single caption). Returns mm, gap included. -->
<xsl:template name="caption-col-width">
  <xsl:variable name="chars">
    <xsl:for-each select="descendant::captionLine">
      <xsl:sort select="string-length(normalize-space())" data-type="number" order="descending"/>
      <xsl:if test="position() = 1"><xsl:value-of select="string-length(normalize-space())"/></xsl:if>
    </xsl:for-each>
  </xsl:variable>
  <xsl:variable name="w" select="$chars * 2.47 + 6"/>   <!-- text + padding + border -->
  <xsl:value-of select="$w * ($w &gt; 20) + 20 * ($w &lt;= 20) + 3"/>  <!-- min 20mm, + 3mm gap -->
</xsl:template>
```
**What to add to each of your templates:**  

| Your template | Add |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| captionGroup → fo:table | table-layout="fixed" width="100%" border-collapse="separate" border-separation="3mm", plus the font settings (Verdana, bold, 9pt, line-height 1.15) from the 12pt fix |
| colspec → fo:table-column | width from the helper, plus a spacer column before the first and after the last (see below) |
| captionBody → fo:table-body | nothing |
| captionRow → fo:table-row | block-progression-dimension.minimum="7.3mm" |
| captionEntry → fo:table-cell | add 1 to its column number; border, padding, centring and colour only when it holds a caption |
| caption inside an entry | nothing, except make sure it adds no margins or spacing of its own |
| captionLine → fo:block | text-align="center" keep-together.within-line="always" |
  
**colspec:** this template outputs the spacer columns too, so captionGroup needs no column changes.  
```
<xsl:template match="captionGroup/colspec">
  <xsl:variable name="w">
    <xsl:for-each select=".."><xsl:call-template name="caption-col-width"/></xsl:for-each>
  </xsl:variable>
  <xsl:if test="not(preceding-sibling::colspec)">
    <fo:table-column column-width="proportional-column-width(1)"/>
  </xsl:if>
  <fo:table-column column-width="{$w}mm"/>
  <xsl:if test="not(following-sibling::colspec)">
    <fo:table-column column-width="proportional-column-width(1)"/>
  </xsl:if>
</xsl:template>
```
Match captionGroup/colspec, not plain colspec. Ordinary tables use the same element name, and a template for plain colspec probably already serves them. The more specific pattern wins automatically, so your table template is left alone.  
**captionEntry:**  
```
<fo:table-cell column-number="{count(preceding-sibling::captionEntry) + 2}">
  <xsl:if test="caption">
    <xsl:attribute name="border">0.35mm solid black</xsl:attribute>
    <xsl:attribute name="padding">1mm 2.5mm</xsl:attribute>
    <xsl:attribute name="display-align">center</xsl:attribute>
    <xsl:attribute name="background-color">
      <xsl:for-each select="caption"><xsl:call-template name="lamp-colour"/></xsl:for-each>
    </xsl:attribute>
  </xsl:if>
  <xsl:apply-templates/>
  <xsl:if test="not(caption)"><fo:block/></xsl:if>
</fo:table-cell>
```
If your entry template already works out column-number from colname/colnum (or spans with namest/nameend), keep that logic and just add 1. The left spacer column shifts every tile one column to the right. This is the change most likely to be missed: without it, tiles land one column to the left and the centring breaks.  
**Single caption** (not in a group): keep the one-cell table from the draft as its own template with match="caption[not(parent::captionEntry)]". The predicate keeps it from catching captions inside a group.  
Two more checks:  
* **If your captionGroup currently uses border-collapse="collapse"**, the gap between tiles disappears, because border-separation only works in the separate model.  
* **If your caption or captionLine templates add space-before, margins or their own wrapper block**, the text sits off centre. Remove those for captions.  
If you paste your current templates, I can mark up the exact changes in them.  
