#include "markerBatch.h"
#include "gl.h"
#include "gl/renderState.h"
#include "gl/shaderProgram.h"
#include "gl/vertexLayout.h"
#include "gl/texture.h"
#include "markers/marker.h"
#include "view/view.h"

namespace Tangram {

MarkerBatch::MarkerBatch() {

    // Initialize shader program and vertex layout

    std::string vertexShaderSource = R"END(
        #ifdef GL_ES
        precision highp float;
        #endif
        uniform mat4 u_viewproj;
        uniform vec2 u_resolution;
        attribute vec2 a_position;
        attribute vec2 a_extent;
        attribute vec2 a_texcoords;
        varying vec2 v_texcoords;
        void main() {
            v_texcoords = a_texcoords;
            gl_Position = u_viewproj * vec4(a_position, 0.0, 1.0);
            gl_Position.xy += a_extent / u_resolution * gl_Position.w;
        }
    )END";

    std::string fragmentShaderSource = R"END(
        #ifdef GL_ES
        precision highp float;
        #endif
        uniform sampler2D u_texture;
        varying vec2 v_texcoords;
        void main(void) {
            gl_FragColor = texture2D(u_texture, v_texcoords);
        }
    )END";

    m_program = std::make_unique<ShaderProgram>();
    m_program->setSourceStrings(fragmentShaderSource, vertexShaderSource);

    m_layout = std::unique_ptr<VertexLayout>(new VertexLayout({
        {"a_position", 2, GL_FLOAT, false, 0},
        {"a_extent", 2, GL_FLOAT, false, 0},
        {"a_texcoords", 2, GL_FLOAT, false, 0},
    }));

}

void MarkerBatch::begin(View& _view) {

    m_view = &_view;
    m_texture = nullptr;
    m_vertices.clear();
    m_indices.clear();

}

void MarkerBatch::draw(const Marker& _marker) {

    auto tex = _marker.texture().get();

    if (m_texture == nullptr) {
        m_texture = tex;
    } else if (m_texture != tex) {
        flush();
        m_texture = tex;
    }

    const auto& projection = m_view->getMapProjection();
    auto origin = glm::dvec2(m_view->getPosition());
    auto position = projection.LonLatToMeters(_marker.coordinates()) - origin;
    auto sprite = _marker.sprite();
    auto size = _marker.size();

    float x = position.x, y = position.y;
    float u1 = sprite[0], u2 = sprite[2];
    float v1 = sprite[1], v2 = sprite[3];
    float w = size.x, h = size.y;

    uint16_t offset = m_vertices.size();

    // Vertices of a quad CCW from bottom left
    m_vertices.push_back({ { x, y }, { 0, 0 }, { u1, v1 } });
    m_vertices.push_back({ { x, y }, { w, 0 }, { u2, v1 } });
    m_vertices.push_back({ { x, y }, { w, h }, { u2, v2 } });
    m_vertices.push_back({ { x, y }, { 0, h }, { u1, v2 } });

    // Indices of two triangles, bottom-right and top-left
    m_indices.push_back(offset + 0);
    m_indices.push_back(offset + 1);
    m_indices.push_back(offset + 2);
    m_indices.push_back(offset + 2);
    m_indices.push_back(offset + 3);
    m_indices.push_back(offset + 0);

}

void MarkerBatch::flush() {

    // Bind current texture
    m_texture->update(0);
    m_texture->bind(0);

    // Set render state
    RenderState::vertexBuffer(0);
    RenderState::indexBuffer(0);
    RenderState::blending(GL_TRUE);
    RenderState::blendingFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    RenderState::depthTest(GL_FALSE);

    // Set uniforms
    m_program->use();
    m_program->setUniformi("u_texture", 0);
    m_program->setUniformMatrix4f("u_viewproj", m_view->getViewProjectionMatrix());
    m_program->setUniformf("u_resolution", m_view->getWidth(), m_view->getHeight());

    // Draw elements
    m_layout->enable(*m_program, 0, m_vertices.data());
    glDrawElements(GL_TRIANGLES, m_indices.size(), GL_UNSIGNED_SHORT, m_indices.data());

    // Clear vertices and indices
    m_vertices.clear();
    m_indices.clear();

}

void MarkerBatch::end() {

    // If element arrays are not empty, flush them
    if (!m_indices.empty()) {
        flush();
    }

    // Reset current texture and view
    m_texture = nullptr;
    m_view = nullptr;

}

}