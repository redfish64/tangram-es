#pragma once

#include <memory>
#include <string>
#include "scene/spriteAtlas.h"
#include "util/types.h"

namespace Tangram {

class Scene;
class Texture;

class Marker {

public:

    Marker(const Scene& _scene, const std::string& _texture, const std::string& _sprite);

    const auto& coordinates() const { return m_coordinates; }
    const auto& rotation() const { return m_rotation; }
    const auto& sprite() const { return m_sprite; }
    const auto& texture() const { return m_texture; }

    void setCoordinates(double _lng, double _lat);
    void setRotation(float _radians);

protected:

    std::shared_ptr<Texture> m_texture;
    SpriteNode m_sprite;
    LngLat m_coordinates;
    float m_rotation;

};

}
