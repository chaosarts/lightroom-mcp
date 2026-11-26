import tempfile
from collections import OrderedDict
from pathlib import Path
from typing import Any
from uuid import UUID, uuid4, uuid5
from xml.etree import ElementTree as ET

from mcp.server.mcpserver.exceptions import ToolError

XMP = "adobe:ns:meta/"
RDF = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
CRS = "http://ns.adobe.com/camera-raw-settings/1.0/"
for prefix, namespace in (("x", XMP), ("rdf", RDF), ("crs", CRS)):
    ET.register_namespace(prefix, namespace)

# Lightroom's SDK and XMP use the same names for these settings.
NUMERIC_SETTINGS = {
    "Texture", "Clarity2012", "Dehaze", "Vibrance", "Saturation",
    "ParametricShadows", "ParametricDarks", "ParametricLights", "ParametricHighlights",
    "ParametricShadowSplit", "ParametricMidtoneSplit", "ParametricHighlightSplit",
    "SplitToningShadowHue", "SplitToningShadowSaturation",
    "SplitToningHighlightHue", "SplitToningHighlightSaturation", "SplitToningBalance",
    "ColorGradeMidtoneHue", "ColorGradeMidtoneSat", "ColorGradeShadowLum",
    "ColorGradeMidtoneLum", "ColorGradeHighlightLum", "ColorGradeBlending",
    "ColorGradeGlobalHue", "ColorGradeGlobalSat", "ColorGradeGlobalLum",
    "PostCropVignetteAmount", "PostCropVignetteMidpoint", "PostCropVignetteFeather",
    "PostCropVignetteRoundness", "PostCropVignetteStyle", "PostCropVignetteHighlightContrast",
    "GrainAmount", "GrainSize", "GrainFrequency",
} | {
    f"{adjustment}Adjustment{color}"
    for adjustment in ("Hue", "Saturation", "Luminance")
    for color in ("Red", "Orange", "Yellow", "Green", "Aqua", "Blue", "Purple", "Magenta")
}
POINT_CURVES = {
    "ToneCurvePV2012", "ToneCurvePV2012Red", "ToneCurvePV2012Green", "ToneCurvePV2012Blue",
}

_previews: OrderedDict[UUID, dict[str, Any]] = OrderedDict()


def remember_preview(requested: dict[str, Any], rendered: dict[str, Any]) -> str:
    preview_id = uuid4()
    _previews[preview_id] = {key: rendered.get(key) for key in requested}
    if len(_previews) > 32:
        _previews.popitem(last=False)
    return preview_id.hex


def _preset_xml(name: str, preset_id: UUID, settings: dict[str, Any]) -> bytes:
    root = ET.Element(ET.QName(XMP, "xmpmeta"))
    rdf = ET.SubElement(root, ET.QName(RDF, "RDF"))
    description = ET.SubElement(rdf, ET.QName(RDF, "Description"))
    description.set(ET.QName(RDF, "about"), "")
    for key, value in {
        "PresetType": "Normal",
        "UUID": preset_id.hex.upper(),
        "SupportsColor": "True",
        "SupportsMonochrome": "True",
        "SupportsHighDynamicRange": "True",
        "SupportsNormalDynamicRange": "True",
        "HasSettings": "True",
    }.items():
        description.set(ET.QName(CRS, key), value)

    label = ET.SubElement(description, ET.QName(CRS, "Name"))
    alternatives = ET.SubElement(label, ET.QName(RDF, "Alt"))
    ET.SubElement(alternatives, ET.QName(RDF, "li"), {
        "{http://www.w3.org/XML/1998/namespace}lang": "x-default",
    }).text = name

    unsupported = []
    for key, value in sorted(settings.items()):
        if key in NUMERIC_SETTINGS and type(value) in (int, float):
            description.set(ET.QName(CRS, key), str(value))
        elif (
            key in POINT_CURVES
            and isinstance(value, list)
            and len(value) >= 4
            and len(value) % 2 == 0
            and all(type(coordinate) is int and 0 <= coordinate <= 255 for coordinate in value)
        ):
            curve = ET.SubElement(description, ET.QName(CRS, key))
            points = ET.SubElement(curve, ET.QName(RDF, "Seq"))
            for index in range(0, len(value), 2):
                ET.SubElement(points, ET.QName(RDF, "li")).text = (
                    f"{value[index]}, {value[index + 1]}"
                )
        else:
            unsupported.append(key)
    if unsupported:
        raise ToolError(
            "These settings could not be exported from the approved preview: "
            + ", ".join(unsupported)
        )
    ET.indent(root)
    return ET.tostring(root, encoding="utf-8")


def export_preset(directory: Path, preview_id: str, name: str) -> dict[str, str]:
    name = name.strip()
    if not name or any(
        ord(char) < 32 or 0xD800 <= ord(char) <= 0xDFFF or char in "\ufffe\uffff"
        for char in name
    ):
        raise ToolError("Supply a preset name with printable characters.")
    try:
        identifier = UUID(preview_id)
        settings = _previews[identifier]
    except (KeyError, ValueError) as error:
        raise ToolError("Preview the look again to obtain a current preview ID.") from error

    preset_id = uuid5(identifier, name)
    data = _preset_xml(name, preset_id, settings)
    path = directory / f"{preset_id.hex}.xmp"
    try:
        directory.mkdir(mode=0o700, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=directory, delete=False) as file:
            temporary = Path(file.name)
            try:
                file.write(data)
                file.close()
                temporary.replace(path)
            finally:
                temporary.unlink(missing_ok=True)
    except OSError as error:
        raise ToolError("Could not write the Lightroom XMP preset.") from error
    return {"name": name, "path": str(path)}
