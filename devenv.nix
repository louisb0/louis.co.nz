{pkgs, ...}: {
  languages.ruby.enable = true;

  packages = with pkgs; [
    rubyPackages_3_4.jekyll
  ];
}
