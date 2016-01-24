#pragma once
#include <cstdint>
#include <memory>
#include <vector>
#include "glm/vec2.hpp"

namespace Tangram {

class Marker;
class ShaderProgram;
class Texture;
class VertexLayout;
class View;

class MarkerBatch {

public:

    MarkerBatch();

    void begin(View& _view);
    void draw(const Marker& _marker);
    void flush();
    void end();

protected:

    using Index = uint16_t;
    using Vertex = struct {
        glm::vec2 position;
        glm::vec2 extent;
        glm::vec2 texcoords;
    };

    std::unique_ptr<ShaderProgram> m_program;
    std::unique_ptr<VertexLayout> m_layout;
    std::vector<Vertex> m_vertices;
    std::vector<Index> m_indices;
    Texture* m_texture = nullptr;
    View* m_view = nullptr;

};

}
