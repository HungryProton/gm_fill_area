# ProtonScatter

![Banner](https://user-images.githubusercontent.com/52043844/232775382-a9b1d1fe-44d3-4f3b-a1f8-73b7b38f1b5f.png)

> ### Place anything you want in your scenes, in a procedural, non-destructive way.


## What is it?

This is an add-on for Godot 4, which automates the positioning of assets in a scene. If you have a lot of props to place, and you would rather not do it by hand, ProtonScatter may be useful to you.


| <video src="https://user-images.githubusercontent.com/52043844/232777856-c364eb48-a001-4b36-a33d-5551bab4c4e9.mp4"> | <video src="https://user-images.githubusercontent.com/52043844/232777949-836c744b-7df7-4d67-8f6e-f176db913d32.mp4"> |
|---------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------|
| Placing grass on arbitrary geometry                                                                                 | Editing the showcase scene                                                                                          |

The showcase scene composition was entirely done using ProtonScatter. First, large rocks are randomly placed within an area, then trees, grass and other details are projected onto the rocks' colliders surface.


## How does it work?

The basic setup is as follows:

![setup](https://user-images.githubusercontent.com/52043844/232782868-83c14fde-eee2-4553-b2a4-42961769f4cf.png)


+ A `ProtonScatter` (1) node holds the `positionning rules` (2) that can be edited in the inspector. This panel is very similar to Blender's modifier stack panel. Some modifiers create points, others change their transforms. You mix different modifiers in order to obtain the result you need.

+ One or more `ScatterItem` nodes to select which asset you want to place.
+ One or more `ScatterShape` items to define the area where the scattering happens.

### Creating points

| ![grid](https://user-images.githubusercontent.com/52043844/232784688-b6bca4e1-9626-412a-94da-13873b903da6.png) | ![random](https://user-images.githubusercontent.com/52043844/232784715-0be37ff1-e08e-483b-9fdb-c2b2483bd5be.png) | ![along_edge](https://user-images.githubusercontent.com/52043844/232784736-c31c4045-6f8d-475f-a4b9-9e0edec44ebf.png) |
|----------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------|
| Placing items aligned on a grid                                                                                | Placing items randomly                                                                                           | Placing items along an edge                                                                                          |

### Defining the domain

Scatter currently ships with three shape types: Box, Sphere and Path. They can be combined to create more complex shapes. Notice how in the last example, the box is shown in red. This means the shape is marked as 'negative' and new items won't appear inside.

| ![box](https://user-images.githubusercontent.com/52043844/232786126-649e70b6-95cb-45c2-9b7c-05b2151a1f4e.png) | ![sphere](https://user-images.githubusercontent.com/52043844/232786140-c170ac21-d2d9-4c7e-b4dd-63635b034415.png) | ![path](https://user-images.githubusercontent.com/52043844/232786175-7fb3acaa-f557-4890-a200-cb9333971280.png) | ![combined_shapes](https://user-images.githubusercontent.com/52043844/232786205-0f0bac90-763b-4373-bdfd-82c63b63bb32.png) |
|---------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------|

### Other uses

Most of the examples above placed items on the floor or on a flat plane, but nothing stops you from using the full 3D space. The mushrooms are placed in the space, then projected in a random direction until they hit a tree. The tower in the background is done by stacking individual bricks using two array modifiers.

https://user-images.githubusercontent.com/52043844/232786762-330314a9-bc8a-49f4-86f7-1cfe99437d7c.mp4

## FAQ

### How to install this addon?

#### Using the asset lib

+ Using the asset lib, look for ProtonScatter and click on Install.
+ If nothing appears, that means the add-on was not accepted yet, so use the manual method.

#### Manually

+ Download or clone this repository.
+ Copy the proton_scatter folder into your project's add-on folder.
+ DO NOT rename the proton_scatter folder, or it won't work.
+ Go to your Projects settings > Plugins > and enable ProtonScatter.

### Does it work on Godot 3.x ?

+ Go to the `v3` branch and install it from there.
+ Keep in mind that ProtonScatter was completely rewritten and overhauled for Godot 4, there will be significant differences.
+ If you're upgrading your project from Godot 3 to Godot 4, the previous Scatter objects will NOT be compatible anymore.

### Where's the documentation?

+ Click on any `ProtonScatter` node and look at the `Modifier Stack` in the inspector.
+ You will see a `Doc` button in the top right corner. Click it to access the built-in documentation.

![image](https://user-images.githubusercontent.com/52043844/232790457-bbb96ae9-42ed-4587-800a-c945d59426db.png)

## Developing

If you cloned this repo locally and want to work on it you will need to install the plugins using the following command to install additional plugins:

```
godot --headless --script plug.gd install
```

### Testing

Scatter uses the [Gut](https://github.com/bitwes/Gut) tool for testing. These tests can be run from the command line using:
```
godot --headless --script addons/gut/gut_cmdln.gd
```

## License

- This add-on is published under the MIT license.
- About the game assets under the `demo` folder:
  + 3D assets are under the MIT license.
  + Most textures bundled with this project have been created with images from Textures.com. You cannot redistribute them on their own, but they're free to use as part of a bigger project. Please visit [www.textures.com](https://www.textures.com/support/faq-license) for more information. 

