#include "markers/marker.h"

#include "platform.h"
#include "scene/scene.h"
#include "scene/spriteAtlas.h"

#include <cmath>

namespace Tangram {

Marker::Marker(const Scene& _scene, const std::string& _texture, const std::string& _sprite) {

    // Locate the sprite that this marker will use
    {
        SpriteNode node;
        const auto& atlases = _scene.spriteAtlases();
        auto it = atlases.find(_texture);
        if (it != atlases.end() && it->second->getSpriteNode(_sprite, node)) {
            m_uvs = { node.m_uvBL.x, node.m_uvBL.y, node.m_uvTR.x, node.m_uvTR.y };
            m_size = node.m_size;
        }
    }

    // Locate the texture that this marker will use
    {
        const auto& textures = _scene.textures();
        auto it = textures.find(_texture);
        if (it != textures.end()) {
            m_texture = it->second;
        }
    }

}

void Marker::setCoordinates(double _lng, double _lat) {

    m_coordinates = { _lng, _lat };

}

void Marker::setCoordinates(double _lng, double _lat, float _duration, EaseType _e) {

    glm::dvec2 start { m_coordinates };
    glm::dvec2 end { _lng, _lat };
    auto cb = [=](float t) {
        auto pos = ease(start, end, t, _e);
        setCoordinates(pos.x, pos.y);
        requestRender();
    };
    m_ease = Ease(_duration, cb);
    requestRender();

}

void Marker::setRotation(float _radians) {

    m_rotation = _radians;

}

void Marker::update(float _dt) {

    if (!m_ease.finished()) {
        m_ease.update(_dt);
    }

}

}
