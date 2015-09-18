#include "polylineStyle.h"

#include "tangram.h"
#include "gl/shaderProgram.h"
#include "scene/stops.h"
#include "tile/tile.h"

namespace Tangram {

PolylineStyle::PolylineStyle(std::string _name, Blending _blendMode, GLenum _drawMode) : Style(_name, _blendMode, _drawMode) {
}

void PolylineStyle::constructVertexLayout() {

    // TODO: Ideally this would be in the same location as the struct that it basically describes
    m_vertexLayout = std::shared_ptr<VertexLayout>(new VertexLayout({
        {"a_position", 3, GL_FLOAT, false, 0},
        {"a_texcoord", 2, GL_FLOAT, false, 0},
        {"a_extrude", 4, GL_FLOAT, false, 0},
        {"a_color", 4, GL_UNSIGNED_BYTE, true, 0},
        {"a_layer", 1, GL_FLOAT, false, 0}
    }));

}

void PolylineStyle::constructShaderProgram() {

    std::string vertShaderSrcStr = stringFromResource("shaders/polyline.vs");
    std::string fragShaderSrcStr = stringFromResource("shaders/polyline.fs");

    m_shaderProgram->setSourceStrings(fragShaderSrcStr, vertShaderSrcStr);
}

PolylineStyle::Parameters PolylineStyle::parseRule(const DrawRule& _rule) const {
    Parameters p;

    uint32_t cap = 0, join = 0;

    _rule.get(StyleParamKey::order, p.order);
    _rule.get(StyleParamKey::color, p.color);
    _rule.get(StyleParamKey::width, p.width);
    _rule.get(StyleParamKey::cap, cap);
    _rule.get(StyleParamKey::join, join);

    p.cap = static_cast<CapTypes>(cap);
    p.join = static_cast<JoinTypes>(join);

    if (_rule.get(StyleParamKey::outline_color, p.outlineColor) |
        _rule.get(StyleParamKey::outline_width, p.outlineWidth) |
        _rule.get(StyleParamKey::outline_cap, cap) |
        _rule.get(StyleParamKey::outline_join, join)) {
        p.outlineOn = true;
        p.outlineCap = static_cast<CapTypes>(cap);
        p.outlineJoin = static_cast<JoinTypes>(join);
    }

    return p;
}

void PolylineStyle::buildLine(const Line& _line, const DrawRule& _rule, const Properties& _props, VboMesh& _mesh, Tile& _tile) const {
    std::vector<PolylineVertex> vertices;

    Parameters params = parseRule(_rule);
    GLuint abgr = params.color;

    float dWdZ = 0.f;
    auto wp = _rule.findParameter(StyleParamKey::width);
    if (wp && wp.stops) {
        dWdZ = wp.stops->evalFloat(_tile.getID().z + 1) - params.width;
    }

    if (Tangram::getDebugFlag(Tangram::DebugFlags::proxy_colors)) {
        abgr = abgr << (_tile.getID().z % 6);
    }

    GLfloat layer = _props.getNumeric("sort_key") + params.order;
    float width = params.width;

    PolyLineBuilder builder {
        [&](const glm::vec3& coord, const glm::vec2& normal, const glm::vec2& uv) {
            glm::vec4 extrude = { normal.x, normal.y, width, dWdZ };
            vertices.push_back({ coord, uv, extrude, abgr, layer });
        },
        [&](size_t sizeHint){ vertices.reserve(sizeHint); },
        params.cap,
        params.join
    };

    Builders::buildPolyLine(_line, builder);

    if (params.outlineOn) {

        GLuint abgrOutline = params.outlineColor;
        float widthOutline = width + params.outlineWidth;

        dWdZ = 0.f;
        auto owp = _rule.findParameter(StyleParamKey::outline_width);
        if (owp && owp.stops) {
            dWdZ = owp.stops->evalFloat(_tile.getID().z + 1) - params.outlineWidth;
        }

        if (params.outlineCap != params.cap || params.outlineJoin != params.join) {
            // need to re-triangulate with different cap and/or join
            builder.cap = params.outlineCap;
            builder.join = params.outlineJoin;
            Builders::buildPolyLine(_line, builder);
        } else {
            // re-use indices from original line
            size_t oldSize = builder.indices.size();
            size_t offset = vertices.size();
            builder.indices.reserve(2 * oldSize);

            for(size_t i = 0; i < oldSize; i++) {
                 builder.indices.push_back(offset + builder.indices[i]);
            }
            for (size_t i = 0; i < offset; i++) {
                const auto& v = vertices[i];
                glm::vec4 extrudeOutline = { v.extrude.x, v.extrude.y, widthOutline, dWdZ };
                vertices.push_back({ v.pos, v.texcoord, extrudeOutline, abgrOutline, layer - 1.f });
            }
        }
    }

    auto& mesh = static_cast<PolylineStyle::Mesh&>(_mesh);
    mesh.addVertices(std::move(vertices), std::move(builder.indices));
}

}
