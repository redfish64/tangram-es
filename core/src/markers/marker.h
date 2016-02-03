#pragma once

#include "glm/vec2.hpp"
#include "glm/vec4.hpp"
#include "util/ease.h"
#include <memory>
#include <string>

namespace Tangram {

class Scene;
class Texture;

class Marker {

public:

    Marker(const Scene& _scene, const std::string& _texture, const std::string& _sprite);

    const auto& coordinates() const { return m_coordinates; }
    const auto& rotation() const { return m_rotation; }
    const auto& size() const { return m_size; }
    const auto& sprite() const { return m_uvs; }
    const auto& texture() const { return m_texture; }

    void setCoordinates(double _lng, double _lat);
    void setCoordinates(double _lng, double _lat, float _duration, EaseType _ease);
    void setRotation(float _radians);

    void update(float _dt);

protected:

    std::shared_ptr<Texture> m_texture;
    glm::dvec2 m_coordinates;
    glm::vec4 m_uvs;
    glm::vec2 m_size;
    Ease m_ease;
    float m_rotation;

};

}
